import 'package:flutter/foundation.dart';

/// tracks whether an owner is currently signed in, globally accessible.
/// Unlike [ClientSession]/[EmployeeSession] there's no profile object for the
/// owner today — just a flag, enough to gate the owner notification listener.
class OwnerSession {
  OwnerSession._();

  static final ValueNotifier<bool> isSignedIn = ValueNotifier<bool>(false);

  static void setSignedIn() {
    isSignedIn.value = true;
  }

  static void clear() {
    isSignedIn.value = false;
  }
}
