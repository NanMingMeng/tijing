import 'package:flutter/material.dart';

import 'screens/ai_search_page.dart';
import 'screens/bank_list_page.dart';
import 'screens/history_page.dart';
import 'screens/home_page.dart';
import 'screens/settings_page.dart';
import 'theme.dart';

class TiJingApp extends StatelessWidget {
  const TiJingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '题镜',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      HomePage(),
      BankListPage(),
      AiSearchPage(),
      HistoryPage(),
      SettingsPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        height: 68,
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '首页'),
          NavigationDestination(icon: Icon(Icons.library_books_outlined), selectedIcon: Icon(Icons.library_books_rounded), label: '题库'),
          NavigationDestination(icon: Icon(Icons.travel_explore_outlined), selectedIcon: Icon(Icons.travel_explore_rounded), label: 'AI 查题'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history_rounded), label: '历史'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '设置'),
        ],
      ),
    );
  }
}
