import 'package:flutter/material.dart';


import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/dashboard_page.dart';


class SmallBizManagerApp extends StatelessWidget {
 const SmallBizManagerApp({super.key});


 @override
 Widget build(BuildContext context) {
   final demoRole = AppConfig.demoRole.trim().isNotEmpty ? AppConfig.demoRole.trim() : 'client';
   final demoToken = AppConfig.demoAuthToken.trim().isNotEmpty
       ? AppConfig.demoAuthToken.trim()
       : (demoRole == 'owner' ? 'dev-owner' : 'dev-client');


   return MaterialApp(
     title: 'Small Biz Manager',
     theme: AppTheme.light(),
     home: DashboardPage(role: demoRole, authToken: demoToken),
     onGenerateRoute: AppRouter.onGenerateRoute,
     debugShowCheckedModeBanner: false,
   );
 }
}
