import 'package:farway/auth/service/auth_service.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  AuthService authService = AuthService();



  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blue[800],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bug_report,
              size: 80,
              color: Colors.white,
            ),
            SizedBox(height: 24),
            Text(
              'Loading...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'wait a second, while it crashes',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            ElevatedButton(
              onPressed: 
              () {
                setState(() {
                  authService.logoutUser();
                });
              },
              child: Text('This button does nothing'),

            ),
          ],
        ),
      ),
    );
  }
}