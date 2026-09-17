import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '/auth/service/auth_check.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['PUBLIC_SUPABASE_URL']!,
    publishableKey: dotenv.env['PUBLIC_SUPABASE_ANON_KEY']!, //aon key
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farway',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AuthCheckWidget(),
    );
  }
}