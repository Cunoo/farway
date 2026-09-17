import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {

  final _supabase = Supabase.instance.client;

  Future<AuthResponse> loginUser(
    String email, String password) =>_supabase.auth.signInWithPassword(
      email: email.trim(), password: password.trim());

  Future<AuthResponse> registerUser(
    String email, String password) =>_supabase.auth.signUp(
      email: email.trim(), password: password.trim());

  Future<void> logoutUser() => _supabase.auth.signOut();
}







// class AuthService {
//   final _supabase = Supabase.instance.client;

//   // return authReponse which contains user and session (where session.accessToken is JWT)
//   Future<AuthResponse?> loginUser(String email, String password) async {
//     debugPrint('Sending to server: $email');
//     try {
//       final response = await _supabase.auth.signInWithPassword(
//         email: email.trim(),
//         password: password.trim(),
//       );
      
//       if (response.session != null) {
//         debugPrint('user logged: ${response.user?.email}');
//         // here you can access the JWT token:
//         debugPrint('JWT Token: ${response.session!.accessToken}');
//         return response;
//       } else {
//         debugPrint('Loggin in failed');
//         return null;
//       }
//     } catch (e) {
//       debugPrint('Error in login: $e');
//       rethrow; //send error to UI, so it can be displayed in a SnackBar
//     }
//   }

//   Future<void> logoutUser() async {
//     try {
//       await _supabase.auth.signOut();
//       debugPrint('User logged out');
//     } catch (e) {
//       debugPrint('Error in logout: $e');
//       rethrow; //send error to UI, so it can be displayed in a SnackBar
//     }
//   }

//   Future<AuthResponse?> registerUser(String email, String password) async {
//     try {
//       debugPrint('Registering user: $email');
//       final response = await _supabase.auth.signUp(
//         email: email.trim(),
//         password: password.trim(),
//       );
//       return response;
//     } catch (e) {
//       debugPrint('Error in registration: $e');
//       rethrow; //send error to UI, so it can be displayed in a SnackBar
//     }
//     finally {
//       debugPrint('Registration process completed for: $email');
//     }
//   }


// }