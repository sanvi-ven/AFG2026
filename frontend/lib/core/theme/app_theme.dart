import 'package:flutter/material.dart';

/// defines the light theme with material 3 design and indigo color scheme
class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: const CardThemeData(margin: EdgeInsets.all(8)),
    );
  }
}
