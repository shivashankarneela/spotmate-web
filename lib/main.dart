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
          seedColor: const Color(0xFFFF4B6E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: initError != null
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

class _AuthGateState extends State<AuthGate> {
  final _supabase = Supabase.instance.client;

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
                  child: CircularProgressIndicator(color: Color(0xFFFF4B6E)),
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
