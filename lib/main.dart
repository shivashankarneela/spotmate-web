import 'core/widgets/chat_keyboard_insets.dart';
import 'core/widgets/notification_permission_prompt.dart';
import 'dart:async';
import 'features/auth/presentation/device_session_gate.dart';

import 'package:flutter/material.dart';
import 'features/chat/presentation/incoming_call_listener.dart';
import 'features/chat/presentation/call_host.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_constants.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/profile/presentation/profile_setup_screen.dart';

String? initError;
final _rootNavigatorKey = GlobalKey<NavigatorState>();

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
      navigatorKey: _rootNavigatorKey,
      builder: initError == null
          ? (context, child) => DeviceSessionGate(child: IncomingCallListener(
                navigatorKey: _rootNavigatorKey,
                child: NotificationPermissionPrompt(
                  child: ChatKeyboardInsets(child: CallHost(child: child!)),
                ),
              ))
          : null,
      title: 'HaloBerry',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF517C6E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        // HaloBerry design system: ivory surfaces, mint controls, berry CTAs.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF98365E),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF98365E),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF517C6E),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF517C6E),
          foregroundColor: Colors.white,
        ),
        dividerColor: const Color(0xFFE2E7E1),
        iconTheme: const IconThemeData(color: Color(0xFF517C6E)),
        scaffoldBackgroundColor: const Color(0xFFFAF8F5),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shadowColor: const Color(0x16000000),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0xFFE2E7E1)),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: Color(0xFF20382E),
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: TextStyle(
            color: Color(0xFF20382E),
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF20382E),
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: Color(0xFF20382E),
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            color: Color(0xFF20382E),
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF728179),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAF8F5),
          foregroundColor: Color(0xFF20382E),
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
            borderSide: BorderSide(color: Color(0xFFE2E7E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFFE2E7E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(
              color: Color(0xFF517C6E),
              width: 1.5,
            ),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: Color(0xFF517C6E),
          unselectedItemColor: Color(0xFF8D9C94),
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
  String? _profileUser;
  bool _signupInProgress = false;
  bool _passwordRecovery = false;
  Future<Map<String, dynamic>?>? _profile;
  Timer? _presenceTimer;
  StreamSubscription<AuthState>? _authPresenceSubscription;
  final _presenceSupabase = Supabase.instance.client;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPresence();
    _authPresenceSubscription = _supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery && mounted) {
        setState(() => _passwordRecovery = true);
      }
      if (state.session != null) {
        _startPresence();
      } else {
        _presenceTimer?.cancel();
      }
    });
  }

  void _startPresence() {
    _presenceTimer?.cancel();
    if (_presenceSupabase.auth.currentUser == null) return;
    _updatePresence();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 20),
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
    _authPresenceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final user = _supabase.auth.currentSession?.user;
        if (_passwordRecovery) {
          return PasswordResetScreen(onFinished: () {
            if (mounted) {
              setState(() {
                _passwordRecovery = false;
                _profileUser = null;
                _profile = null;
              });
            }
          });
        }

        if (user == null || _signupInProgress) {
          _profileUser = null;
          _profile = null;
          return AuthScreen(onSignupInProgress: (value) {
            if (mounted && _signupInProgress != value) {
              setState(() => _signupInProgress = value);
            }
          });
        }

        if (_profileUser != user.id || _profile == null) {
          _profileUser = user.id;
          _profile = _supabase.from('user_profiles')
              .select('id,name,username,date_of_birth,city_id,bio')
              .eq('id', user.id).maybeSingle();
        }
        return FutureBuilder<Map<String, dynamic>?>(
          key: ValueKey(user.id),
          future: _profile,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF517C6E)),
                ),
              );
            }

            if (profileSnapshot.hasError) {
              return Scaffold(body: Center(child: TextButton(
                onPressed: () => setState(() => _profile = null),
                child: const Text('Could not load your account. Retry'),
              )));
            }
            final profile = profileSnapshot.data;

            // If profile exists with date of birth or name, immediately go to HomeScreen!
            if (profile != null && profile['date_of_birth'] != null &&
                profile['username'] != null && profile['city_id'] != null &&
                (profile['bio'] as String? ?? '').trim().runes.length >= 50) {
              return const HomeScreen();
            }

            // Only brand-new uncompleted accounts see the one-time onboarding
            return ProfileSetupScreen(
              onProfileCompleted: () {
                setState(() => _profile = null);
              },
            );
          },
        );
      },
    );
  }
}










