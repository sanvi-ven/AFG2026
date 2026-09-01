/// made withe the help of chatgpt 4.0, prompt: Help me structure the main Flutter app for a business management platform with routing, theme setup
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/services/client_profile_service.dart';
import 'core/services/employee_profile_service.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/message_service.dart';
import 'core/state/client_session.dart';
import 'core/state/employee_session.dart';
import 'core/state/owner_session.dart';
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
    final useDemoRole = demoRole == 'owner' || demoRole == 'client' || demoRole == 'employee';
    final demoToken = AppConfig.demoAuthToken.trim().isNotEmpty
        ? AppConfig.demoAuthToken.trim()
        : (demoRole == 'owner'
            ? 'dev-owner'
            : demoRole == 'employee'
                ? 'dev-employee'
                : 'dev-client');

    return MaterialApp(
      title: 'Anchor',
      theme: AppTheme.light(),
      builder: (context, child) {
        // wrap app with notification listeners to recieve messages
        return _ClientNotificationListener(
          child: _OwnerNotificationListener(
            child: child ?? const SizedBox.shrink(),
          ),
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

class _OwnerNotificationListener extends StatefulWidget {
  const _OwnerNotificationListener({required this.child});

  final Widget child;

  /// listen for new client-authored replies and show local notifications
  @override
  State<_OwnerNotificationListener> createState() => _OwnerNotificationListenerState();
}

class _OwnerNotificationListenerState extends State<_OwnerNotificationListener> {
  StreamSubscription<List<ClientThreadSummary>>? _subscription;
  bool _bootstrapDone = false;
  Set<String> _knownMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    OwnerSession.isSignedIn.addListener(_syncSubscription);
    _syncSubscription();
  }

  @override
  void dispose() {
    OwnerSession.isSignedIn.removeListener(_syncSubscription);
    _subscription?.cancel();
    super.dispose();
  }

  void _syncSubscription() {
    if (!OwnerSession.isSignedIn.value) {
      _bootstrapDone = false;
      _knownMessageIds = <String>{};
      _subscription?.cancel();
      _subscription = null;
      return;
    }

    if (_subscription != null) {
      return;
    }

    _bootstrapDone = false;
    _knownMessageIds = <String>{};

    _subscription = MessageService.watchClientThreads().listen((threads) async {
      final latestClientMessages = threads
          .where((thread) => thread.lastMessage.senderRole == 'client')
          .map((thread) => thread.lastMessage)
          .toList();

      // on first load, just collect known ids without showing notificaitons
      if (!_bootstrapDone) {
        _knownMessageIds = latestClientMessages.map((item) => item.id).toSet();
        _bootstrapDone = true;
        return;
      }

      for (final message in latestClientMessages) {
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

/// gate to show the dashboard or login based on real Firebase Auth state.
/// Firebase's SDK persists the signed-in user itself across app restarts —
/// this just reacts to whatever authStateChanges() reports, reading the
/// role custom claim off a fresh ID token and loading the matching profile.
class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  StreamSubscription<User?>? _authSubscription;
  bool _loaded = false;
  String? _role;
  String? _authToken;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(_onAuthStateChanged);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      ClientSession.clear();
      EmployeeSession.clear();
      OwnerSession.clear();
      if (mounted) {
        setState(() {
          _role = null;
          _authToken = null;
          _loaded = true;
        });
      }
      return;
    }

    // The role claim is set server-side by /auth/complete-signup, which
    // runs just after the sign-in event that triggers this listener — so a
    // brand-new signup can race this check and briefly show no role at all,
    // which used to sign the user right back out mid-signup even though
    // account creation had actually succeeded. Retry a few times before
    // concluding the account is genuinely orphaned (signed in via the SDK
    // but never completed signup, e.g. an abandoned prior session) rather
    // than a real signup still finishing.
    var tokenResult = await user.getIdTokenResult();
    var role = tokenResult.claims?['role'] as String?;
    for (var attempt = 0; role == null && attempt < 5; attempt++) {
      await Future.delayed(const Duration(milliseconds: 600));
      tokenResult = await user.getIdTokenResult(true);
      role = tokenResult.claims?['role'] as String?;
    }

    switch (role) {
      case 'client':
        final profile = await ClientProfileService.fetchByUid(user.uid);
        if (profile != null) ClientSession.setProfile(profile);
      case 'employee':
        final profile = await EmployeeProfileService.fetchByUid(user.uid);
        if (profile != null) EmployeeSession.setProfile(profile);
      case 'owner':
        OwnerSession.setSignedIn();
      default:
        // signed in but never finished signup (no role claim) — clean slate
        await FirebaseAuth.instance.signOut();
    }

    if (!mounted) return;
    setState(() {
      _role = role;
      _authToken = tokenResult.token;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // show loading spinner while the auth state resolves
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_role != null && _authToken != null) {
      return DashboardPage(role: _role!, authToken: _authToken);
    }
    return const LoginPage();
  }
}
