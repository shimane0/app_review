/// Abstraction for persisting review tracking state.
///
/// [ReviewController] uses this interface to read and write
/// action counts, request counts, and the first-launch
/// timestamp. Implement this with your preferred storage
/// backend (e.g. SharedPreferences, Drift, Hive).
///
/// An [InMemoryReviewStateStore] is provided for testing.
abstract interface class ReviewStateStore {
  /// The number of recorded user actions.
  Future<int> getActionCount();

  /// Persist the action count.
  Future<void> setActionCount(int count);

  /// The number of review requests already made.
  Future<int> getRequestCount();

  /// Persist the request count.
  Future<void> setRequestCount(int count);

  /// The timestamp of the first recorded launch, or `null`
  /// if not yet recorded.
  Future<DateTime?> getFirstLaunchedAt();

  /// Persist the first-launch timestamp.
  Future<void> setFirstLaunchedAt(DateTime date);

  /// The timestamp of the last review request, or `null`
  /// if no review has been requested yet.
  Future<DateTime?> getLastRequestedAt();

  /// Persist the last-review-request timestamp.
  Future<void> setLastRequestedAt(DateTime date);

  /// Clear all persisted review state.
  Future<void> clear();
}

/// In-memory implementation of [ReviewStateStore] for testing.
///
/// All data is lost when the instance is garbage-collected.
class InMemoryReviewStateStore implements ReviewStateStore {
  int _actionCount = 0;
  int _requestCount = 0;
  DateTime? _firstLaunchedAt;
  DateTime? _lastRequestedAt;

  @override
  Future<int> getActionCount() async => _actionCount;

  @override
  Future<void> setActionCount(int count) async => _actionCount = count;

  @override
  Future<int> getRequestCount() async => _requestCount;

  @override
  Future<void> setRequestCount(int count) async => _requestCount = count;

  @override
  Future<DateTime?> getFirstLaunchedAt() async => _firstLaunchedAt;

  @override
  Future<void> setFirstLaunchedAt(DateTime date) async => _firstLaunchedAt = date;

  @override
  Future<DateTime?> getLastRequestedAt() async => _lastRequestedAt;

  @override
  Future<void> setLastRequestedAt(DateTime date) async => _lastRequestedAt = date;

  @override
  Future<void> clear() async {
    _actionCount = 0;
    _requestCount = 0;
    _firstLaunchedAt = null;
    _lastRequestedAt = null;
  }
}
