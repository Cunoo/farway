import 'package:flutter/material.dart';
import 'package:farway/screens/home.dart'; // Import vašej domovskej stránky

class MainTabBar extends StatefulWidget {
  const MainTabBar({super.key});

  @override
  State<MainTabBar> createState() => _MainTabBarState();
}

class _MainTabBarState extends State<MainTabBar> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomePage(),
    const Center(child: Icon(Icons.search, size: 100, color: Colors.green)), // Druhá záložka
    const Center(child: Icon(Icons.person, size: 100, color: Colors.orange)), // Tretia záložka
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}