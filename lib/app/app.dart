import 'package:flutter/material.dart';

import 'main_navigation.dart';

class GameToolApp extends StatelessWidget {
  const GameToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Tool - Texture & Audio Packer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}
