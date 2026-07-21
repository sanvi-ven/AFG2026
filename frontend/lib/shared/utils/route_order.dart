import '../../models/scheduled_work.dart';

/// shared route-sequence ordering for a single team's jobs on a single day,
/// used by both the owner's editable Today's Route tab and the employee's
/// read-only Route tab so both show the identical sequence.
///
/// jobs with a manually-set [ScheduledWork.routeOrder] come first, in ascending
/// routeOrder; any jobs not yet sequenced (null routeOrder) are appended after
/// all ordered ones, sub-sorted among themselves by scheduledDate ascending.
///
/// returns a new sorted list; the input is not mutated.
List<ScheduledWork> sortByRouteOrder(List<ScheduledWork> jobs) {
  final sorted = [...jobs];
  sorted.sort((a, b) {
    final aOrder = a.routeOrder;
    final bOrder = b.routeOrder;
    if (aOrder != null && bOrder != null) {
      final byOrder = aOrder.compareTo(bOrder);
      if (byOrder != 0) return byOrder;
      final byDate = a.scheduledDate.compareTo(b.scheduledDate);
      if (byDate != 0) return byDate;
      return a.id.compareTo(b.id); // deterministic final tiebreaker
    }
    // ordered jobs always sort before unordered ones
    if (aOrder != null) return -1;
    if (bOrder != null) return 1;
    // both unordered: fall back to scheduled time
    final byDate = a.scheduledDate.compareTo(b.scheduledDate);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// [ScheduledWork.routeOrder] is only meaningful *within one bucket* — jobs
/// sharing a team, or jobs individually assigned (no team) — the same
/// scoping [ScheduledWorkService.reorderJobs] and the owner's Today's Route
/// tab use (bucket key = `job.teamId?.trim() ?? ''`, one shared "no team"
/// bucket for both truly-unassigned and individually-assigned jobs). A flat
/// [sortByRouteOrder] call across jobs from DIFFERENT buckets would compare
/// unrelated routeOrder numbers against each other, producing an
/// interleaving that reflects neither bucket's real sequence.
///
/// Use this instead whenever the input list might span more than one
/// team/assignment bucket (e.g. an employee's day that mixes their team's
/// jobs with jobs individually assigned to them) — it sorts each bucket with
/// [sortByRouteOrder] independently, then concatenates bucket results in a
/// stable order (non-empty team ids ascending, the shared "no team" bucket
/// last).
List<ScheduledWork> sortJobsAcrossBuckets(List<ScheduledWork> jobs) {
  final byBucket = <String, List<ScheduledWork>>{};
  for (final job in jobs) {
    final bucketKey = job.teamId?.trim() ?? '';
    byBucket.putIfAbsent(bucketKey, () => <ScheduledWork>[]).add(job);
  }
  final bucketKeys = byBucket.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty && b.isEmpty) return 0;
      if (a.isEmpty) return 1;
      if (b.isEmpty) return -1;
      return a.compareTo(b);
    });
  return [
    for (final bucketKey in bucketKeys) ...sortByRouteOrder(byBucket[bucketKey]!),
  ];
}
