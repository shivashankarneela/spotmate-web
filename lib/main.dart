import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_constants.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/profile/presentation/profile_setup_screen.dart';

String? initError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (SupabaseConstants.supabaseAnonKey.isEmpty) {
      throw StateError('Missing SUPABASE_PUBLISHABLE_KEY. Pass it using --dart-define.');
    }
    await Supabase.initialize(
      url: SupabaseConstants.supabaseUrl,
      anonKey: SupabaseConstants.supabaseAnonKey,
    );
  } catch (e) {
    initError = e.toString();
  }

  runApp(const SpotmateApp());
}

class SpotmateApp extends StatelessWidget {
  const SpotmateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPOTMATE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF162544),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F8F9),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1.5,
          shadowColor: const Color(0x16000000),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: Color(0xFF17213B),
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: TextStyle(
            color: Color(0xFF17213B),
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF17213B),
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: Color(0xFF17213B),
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF17213B),
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF737887),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F8F9),
          foregroundColor: Color(0xFF17213B),
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFFE7E8EE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFFE7E8EE)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(
              color: Color(0xFF162544),
              width: 1.5,
            ),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF162544),
          unselectedItemColor: Color(0xFF9296A3),
          selectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 12,
          ),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
      ),      home: initError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Init Error: $initError', style: const TextStyle(color: Colors.red)),
                ),
              ),
            )
          : const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  Timer? _presenceTimer;
  final _presenceSupabase = Supabase.instance.client;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPresence();
  }

  void _startPresence() {
    _presenceTimer?.cancel();
    _updatePresence();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updatePresence(),
    );
  }

  Future<void> _updatePresence() async {
    final user = _presenceSupabase.auth.currentUser;
    if (user == null) return;
    try {
      await _presenceSupabase.from('user_profiles').update({
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPresence();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _presenceTimer?.cancel();
      _updatePresence();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? _supabase.auth.currentSession;
        final user = session?.user ?? _supabase.auth.currentUser;

        if (user == null) {
          return const AuthScreen();
        }

        // Dynamically verify if this user already completed onboarding
        return FutureBuilder<Map<String, dynamic>?>(
          future: _supabase
              .from('user_profiles')
              .select('id, name, date_of_birth')
              .eq('id', user.id)
              .maybeSingle(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF162544)),
                ),
              );
            }

            final profile = profileSnapshot.data;

            // If profile exists with date of birth or name, immediately go to HomeScreen!
            if (profile != null && profile['date_of_birth'] != null) {
              return const HomeScreen();
            }

            // Only brand-new uncompleted accounts see the one-time onboarding
            return ProfileSetupScreen(
              onProfileCompleted: () {
                setState(() {}); // Instantly navigates to HomeScreen
              },
            );
          },
        );
      },
    );
  }
}










