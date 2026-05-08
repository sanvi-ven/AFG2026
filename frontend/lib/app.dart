/// made withe the help of chatgpt 4.0, prompt: Help me structure the main Flutter app for a business management platform with routing, theme setup

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

/// root widget for the anchor app with theme, routing, and notification listeners
class AnchorApp extends StatelessWidget {
  const AnchorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // check if demo mode is enabled to skip auth for development
    final demoRole = AppConfig.demoRole.trim();
    final useDemoRole = demoRole == 'owner' || demoRole == 'client';
    final demoToken = AppConfig.demoAuthToken.trim().isNotEmpty
        ? AppConfig.demoAuthToken.trim()
        : (demoRole == 'owner' ? 'dev-owner' : 'dev-client');

    return MaterialApp(
      title: 'Anchor',
      theme: AppTheme.light(),
      builder: (context, child) {
        // wrap app with notification listener to recieve messages
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

  /// listen to real-time client messages and show local notifications when received
  @override
  State<_ClientNotificationListener> createState() => _ClientNotificationListenerState();
}

class _ClientNotificationListenerState extends State<_ClientNotificationListener> {
  // subscription to message stream for current client
  StreamSubscription<List<MessageLog>>? _subscription;
  // track which client we're listening to
  String? _activeClientId;
  // flag to skip showing notificaitons on initial load
  bool _bootstrapDone = false;
  // set of message ids already seen to avoid duplicate notificaitons
  Set<String> _knownMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    // listen for profile changes and update subscription
    ClientSession.profile.addListener(_syncSubscription);
    _syncSubscription();
  }

  @override
  void dispose() {
    // cleanup subscription and listener on widget dispose
    ClientSession.profile.removeListener(_syncSubscription);
    _subscription?.cancel();
    super.dispose();
  }

  void _syncSubscription() {
    // extract client id from session profile
    final rawClientId = ClientSession.profile.value?.signupId;
    final clientId = rawClientId?.trim();
    // reset state if no client id available
    if (clientId == null || clientId.isEmpty) {
      _activeClientId = null;
      _bootstrapDone = false;
      _knownMessageIds = <String>{};
      _subscription?.cancel();
      _subscription = null;
      return;
    }

    // if already subscribed to this client, skip resubscription
    if (_activeClientId == clientId && _subscription != null) {
      return;
    }

    // setup new subscription for this client
    _activeClientId = clientId;
    _bootstrapDone = false;
    _knownMessageIds = <String>{};
    _subscription?.cancel();

    // subscribe to message stream for client and show notificaitons for new ones
    _subscription = MessageService.watchClientMessages(clientId: clientId).listen((messages) async {
      // on first load, just collect known ids without showing notificaitons
      if (!_bootstrapDone) {
        _knownMessageIds = messages.map((item) => item.id).toSet();
        _bootstrapDone = true;
        return;
      }

      // check for new messages and show notificaitons for unread ones
      for (final message in messages) {
        if (_knownMessageIds.contains(message.id)) {
          continue;
        }
        _knownMessageIds.add(message.id);
        if (!message.read) {
          // show local notification for new unread message
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

/// gate to show dashboard or session restore based on persist stored session
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  // flag for session loading state
  bool _loaded = false;
  // restored session from persisted storage
  RestoredSession? _session;

  @override
  void initState() {
    super.initState();
    // attempt to restore session from local storage
    _loadSession();
  }

  Future<void> _loadSession() async {
    // load persisted session from storage
    final session = await SessionPersistenceService.loadSession();
    // restore profile to session state if available
    if (session?.role == 'client' && session?.profile != null) {
      ClientSession.setProfile(session!.profile!);
    }
    // update ui once session loading completes
    if (mounted) {
      setState(() {
        _session = session;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // show loading spinner while session loads
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final session = _session;
    // show dashboard if session exists, otherwise show login
    if (session != null) {
      return DashboardPage(
        role: session.role,
        authToken: session.role == 'owner' ? 'dev-owner' : 'dev-client',
      );
    }
    return const LoginPage();
  }
}
