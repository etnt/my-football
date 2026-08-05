import 'package:flutter/material.dart';

import 'features/home/home_shell.dart';

/// Root application widget.
class MyFootballApp extends StatelessWidget {
  const MyFootballApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Football',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
