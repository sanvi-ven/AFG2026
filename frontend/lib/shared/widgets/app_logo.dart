import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 24,
    this.fallbackIcon,
  });

  static const assetPath = 'assets/logos/logo.png';

  final double size;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return Icon(
            fallbackIcon ?? Icons.anchor,
            size: size,
          );
        },
      ),
    );
  }
}