import 'package:flutter/foundation.dart';

import '../../models/client_profile.dart';

/// manages the current client session state globally accessible from anywhere
class ClientSession {
  ClientSession._();

  static final ValueNotifier<ClientProfile?> profile = ValueNotifier<ClientProfile?>(null);

  /// update the current client profile in session
  static void setProfile(ClientProfile value) {
    profile.value = value;
  }

  /// clear the client profile and end the session
  static void clear() {
    profile.value = null;
  }
}
