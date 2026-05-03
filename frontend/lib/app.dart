import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/message_service.dart';
import 'core/services/session_persistence_service.dart';
import 'core/state/client_session.dart';
import 'core/theme/app_theme.dart';
import 'models/message.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';

class SmallBizManagerApp extends StatelessWidget {
  const SmallBizManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final demoRole = AppConfig.demoRole.trim();
    final useDemoRole = demoRole == 'owner' || demoRole == 'client';
    final demoToken = AppConfig.demoAuthToken.trim().isNotEmpty
        ? AppConfig.demoAuthToken.trim()
        : (demoRole == 'owner' ? 'dev-owner' : 'dev-client');

    return MaterialApp(
      title: 'Anchor',
      theme: AppTheme.light(),
      builder: (context, child) {
        return _ClientNotificationListener(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: useDemoRole
          ? DashboardPage(role: demoRole, authToken: demoToken)
          : const _SessionGate(),
      onGenerateRoute: AppRouter.onGenerateRoute,
      debugShowCheckedModeBanner: false,
    );
  }
}

class _ClientNotificationListener extends StatefulWidget {
  const _ClientNotificationListener({required this.child});

  final Widget child;

  @override
  State<_ClientNotificationListener> createState() => _ClientNotificationListenerState();
}

class _ClientNotificationListenerState extends State<_ClientNotificationListener> {
  StreamSubscription<List<MessageLog>>? _subscription;
  String? _activeClientId;
  bool _bootstrapDone = false;
  Set<String> _knownMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    ClientSession.profile.addListener(_syncSubscription);
    _syncSubscription();
  }

  @override
  void dispose() {
    ClientSession.profile.removeListener(_syncSubscription);
    _subscription?.cancel();
    super.dispose();
  }

  void _syncSubscription() {
    final rawClientId = ClientSession.profile.value?.signupId;
    final clientId = rawClientId?.trim();
    if (clientId == null || clientId.isEmpty) {
      _activeClientId = null;
      _bootstrapDone = false;
      _knownMessageIds = <String>{};
      _subscription?.cancel();
      _subscription = null;
      return;
    }

    if (_activeClientId == clientId && _subscription != null) {
      return;
    }

    _activeClientId = clientId;
    _bootstrapDone = false;
    _knownMessageIds = <String>{};
    _subscription?.cancel();

    _subscription = MessageService.watchClientMessages(clientId: clientId).listen((messages) async {
      if (!_bootstrapDone) {
        _knownMessageIds = messages.map((item) => item.id).toSet();
        _bootstrapDone = true;
        return;
      }

      for (final message in messages) {
        if (_knownMessageIds.contains(message.id)) {
          continue;
        }
        _knownMessageIds.add(message.id);
        if (!message.read) {
          await LocalNotificationService.showMessageNotification(
            id: message.id.hashCode,
            title: message.title,
            body: message.body,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  bool _loaded = false;
  RestoredSession? _session;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await SessionPersistenceService.loadSession();
    if (session?.role == 'client' && session?.profile != null) {
      ClientSession.setProfile(session!.profile!);
    }
    if (mounted) {
      setState(() {
        _session = session;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    if (session != null) {
      return DashboardPage(
        role: session.role,
        authToken: session.role == 'owner' ? 'dev-owner' : 'dev-client',
      );
    }
    return const LoginPage();
  }
}
