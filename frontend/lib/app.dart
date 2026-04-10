import 'package:flutter/material.dart';


import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';


class SmallBizManagerApp extends StatelessWidget {
 const SmallBizManagerApp({super.key});


 @override
 Widget build(BuildContext context) {
   return MaterialApp(
     title: 'Small Biz Manager',
     theme: AppTheme.light(),
     initialRoute: AppRouter.login,
     onGenerateRoute: AppRouter.onGenerateRoute,
     debugShowCheckedModeBanner: false,
   );
 }
}
