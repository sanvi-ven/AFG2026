import 'package:flutter/foundation.dart';

import '../../models/client_profile.dart';

class ClientSession {
  ClientSession._();

  static final ValueNotifier<ClientProfile?> profile = ValueNotifier<ClientProfile?>(null);

  static void setProfile(ClientProfile value) {
    profile.value = value;
  }

  static void clear() {
    profile.value = null;
  }
}
