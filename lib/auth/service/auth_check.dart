import 'package:farway/ui/tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../login.dart';
class AuthCheckWidget extends StatelessWidget {
  const AuthCheckWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // While the initial state is loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Check if we have a current session (i.e., a valid JWT / logged-in user)
        final session = supabase.auth.currentSession;
        debugPrint('Current session: $session');

        if (session != null) {
          // user is logged in, show the home page
          return const MainTabBar(); 
        } else {
          // user is NOT logged in, show the login page
          return const LoginPage();
        }
      },
    );
  }
}