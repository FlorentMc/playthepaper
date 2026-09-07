import 'package:flutter/material.dart';

/// Placeholder until the news module lands.
class FrontPageScreen extends StatelessWidget {
  const FrontPageScreen({super.key, required this.dateText});
  final String dateText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Front Page')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}
