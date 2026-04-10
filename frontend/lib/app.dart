import 'package:flutter/material.dart';




import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/login_page.dart';




class SmallBizManagerApp extends StatelessWidget {
const SmallBizManagerApp({super.key});




@override
Widget build(BuildContext context) {
  return MaterialApp(
    title: 'Anchor',
    theme: AppTheme.light(),
    home: const LoginPage(),
    onGenerateRoute: AppRouter.onGenerateRoute,
    debugShowCheckedModeBanner: false,
  );
}
}
