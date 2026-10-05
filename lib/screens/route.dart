import 'package:farway/auth/service/auth_service.dart';
import 'package:farway/ui/app_colors.dart';
import 'package:flutter/material.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage> {

  AuthService authService = AuthService();



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routes',
          style: TextStyle(
            color: AppColors.teal,
          )
        ),
        
        backgroundColor: AppColors.surface,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('This is the Routes Page'),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}