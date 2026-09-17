import 'package:farway/screens/register.dart';
import 'package:flutter/material.dart';
import 'package:farway/ui/my_text_field.dart';
import 'package:farway/auth/service/auth_service.dart';
import 'package:farway/utils/auth_ui_helper.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with AuthUiHelper {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  void _onLoginPressed() {
    runAuthAction(
      () async {
        await _authService.loginUser(
          _emailController.text,
          _passwordController.text,
        );
      },
      successMessage: 'Successfully logged in!',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Farway'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Login'),
            const SizedBox(height: 16),
            SizedBox(
              width: 300,
              child: MyTextField(
                labelText: 'Email',
                hintText: 'Enter your email',
                controller: _emailController,
                obscureText: false,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 300,
              child: MyTextField(
                labelText: 'Password',
                hintText: 'Enter your password',
                controller: _passwordController,
                obscureText: true,
              ),
            ),
            TextButton(
              onPressed: () {
                // Navigate to the registration page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterPage(),
                  ),
                );
              },
              child: Text("Don't have an account? Sign up"),
            ),
            const SizedBox(height: 24),
            isLoading_AuthUiHelper
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _onLoginPressed,
                    child: const Text('Log in'),
                  ),
          ],
        ),
      ),
    );
  }
}