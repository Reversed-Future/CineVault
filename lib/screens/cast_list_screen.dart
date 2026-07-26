import 'package:flutter/material.dart';

class CastListScreen extends StatelessWidget {
  const CastListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('演职员')),
      body: const Center(
        child: Text('CineVault 当前不提供独立演职员页面'),
      ),
    );
  }
}
