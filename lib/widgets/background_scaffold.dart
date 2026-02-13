import 'package:flutter/material.dart';

class BackgroundScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final bool extendBodyBehindAppBar;

  const BackgroundScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
    this.extendBodyBehindAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/wallpapers/wallpaper_empty.jpeg',
              fit: BoxFit.cover,
            ),
          ),
          child,
        ],
      ),
    );
  }
}