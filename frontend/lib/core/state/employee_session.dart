import 'package:flutter/foundation.dart';

import '../../models/employee_profile.dart';

/// manages the current employee session state globally accessible from anywhere
class EmployeeSession {
  EmployeeSession._();

  static final ValueNotifier<EmployeeProfile?> profile = ValueNotifier<EmployeeProfile?>(null);

  /// update the current employee profile in session
  static void setProfile(EmployeeProfile value) {
    profile.value = value;
  }

  /// clear the employee profile and end the session
  static void clear() {
    profile.value = null;
  }
}
