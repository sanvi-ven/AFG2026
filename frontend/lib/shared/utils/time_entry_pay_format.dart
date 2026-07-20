import '../../core/services/reporting_service.dart';
import '../../models/employee_profile.dart';
import '../../models/time_entry.dart';

/// shared display string for a single time entry's calculated pay, used on
/// both the owner's Team → Time Entries tab and the employee's own My Hours
/// page so the same day shows identically-worded numbers in both places.
String formatEntryPay(TimeEntry entry, EmployeeProfile? employee) {
  final rate = ReportingService.effectiveRateForEntry(entry, employee);
  if (rate <= 0) {
    return 'Rate not set';
  }

  final hours = ReportingService.hoursForEntry(entry);
  final payout = ReportingService.payoutForEntry(entry, employee);
  final overrideSuffix = entry.wageOverride != null ? ' (override)' : '';
  return '${hours.toStringAsFixed(1)}h × \$${rate.toStringAsFixed(2)}/hr = \$${payout.toStringAsFixed(2)}$overrideSuffix';
}
