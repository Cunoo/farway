import 'package:farway/auth/service/auth_service.dart';
import 'package:farway/ui/my_text_field.dart';
import 'package:farway/utils/auth_ui_helper.dart';
import 'package:flutter/material.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState(); // Zmena z _RegisterPageState na State<RegisterPage>
}

class _RegisterPageState extends State<RegisterPage> with AuthUiHelper {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onRegisterPressed({String successMessage = "Registration successful!"}) {
    runAuthAction(() => _authService.registerUser(
      _emailController.text, _passwordController.text),
      successMessage: successMessage,
      popOnSuccess: true);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
      ),
      body:
      Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
              const SizedBox(height: 24),
              isLoading_AuthUiHelper // variable from mixin AuthUiHelper
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _onRegisterPressed, // Prepojené na registráciu
                      child: const Text('Register'),
                    ),
            ],
          ),
        ),
    );
  }
}