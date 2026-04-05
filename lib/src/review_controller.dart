import 'package:shared_preferences/shared_preferences.dart';

import 'app_review_client.dart';
import 'messages.g.dart';

/// Configuration for [ReviewController] conditions.
///
/// All conditions must be met for a review request to fire.
/// ```dart
/// const config = ReviewCondition(
///   minDaysFromFirstLaunch: 7,
///   minActionCount: 3,
///   maxRequestCount: 3,
/// );
/// ```
class ReviewCondition {
  /// Creates a [ReviewCondition].
  const ReviewCondition({
    this.minDaysFromFirstLaunch = 3,
    this.minActionCount = 1,
    this.maxRequestCount = 3,
  });

  /// Minimum days since the first recorded launch before
  /// a review request is eligible.
  final int minDaysFromFirstLaunch;

  /// Minimum number of recorded user actions (e.g. shares,
  /// completions) before a review request is eligible.
  final int minActionCount;

  /// Maximum number of review requests the app will make.
  /// After this limit, [requestReviewIfEligible] always
  /// returns `false` without calling the native API.
  final int maxRequestCount;
}

/// Smart review request controller with condition management.
///
/// Tracks user activity and first-launch date via
/// [SharedPreferences], and requests a review only when
/// all configured conditions are met.
///
/// ```dart
/// final controller = ReviewController(
///   condition: const ReviewCondition(
///     minDaysFromFirstLaunch: 3,
///     minActionCount: 1,
///     maxRequestCount: 3,
///   ),
/// );
///
/// // Call once at app startup
/// await controller.recordFirstLaunch();
///
/// // Call each time the user completes a key action
/// await controller.recordAction();
///
/// // Check conditions and request review if eligible
/// final didRequest = await controller.requestReviewIfEligible();
/// ```
class ReviewController {
  /// Creates a [ReviewController].
  ///
  /// - [condition]: The conditions that must be met.
  /// - [client]: An [AppReviewClient] instance. If null,
  ///   a default instance is created.
  /// - [onReviewRequested]: Optional callback invoked after
  ///   a review is requested, with the [ReviewResult].
  ///   Useful for analytics logging.
  ReviewController({
    this.condition = const ReviewCondition(),
    AppReviewClient? client,
    this.onReviewRequested,
  }) : _client = client ?? AppReviewClient();

  /// The conditions that must all be met for a review request.
  final ReviewCondition condition;

  final AppReviewClient _client;

  /// Optional callback invoked after a review request completes.
  final void Function(ReviewResult result)? onReviewRequested;

  // SharedPreferences keys
  static const _keyFirstLaunchedAt = 'app_review_first_launched_at';
  static const _keyActionCount = 'app_review_action_count';
  static const _keyRequestCount = 'app_review_request_count';

  /// Record the app's first launch timestamp.
  ///
  /// Call this once during app initialization. If already
  /// recorded, this is a no-op.
  Future<void> recordFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyFirstLaunchedAt) != null) return;
    await prefs.setString(_keyFirstLaunchedAt, DateTime.now().toIso8601String());
  }

  /// Record a user action (e.g. share, save, complete).
  ///
  /// Increments the internal action counter used for
  /// eligibility checking.
  Future<void> recordAction() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyActionCount) ?? 0;
    await prefs.setInt(_keyActionCount, current + 1);
  }

  /// Check all conditions and request a review if eligible.
  ///
  /// Returns `true` if a review request was actually made
  /// (regardless of whether the OS showed the dialog).
  ///
  /// Returns `false` if any condition was not met or the
  /// request failed.
  Future<bool> requestReviewIfEligible() async {
    final prefs = await SharedPreferences.getInstance();

    // Condition 1: action count
    final actionCount = prefs.getInt(_keyActionCount) ?? 0;
    if (actionCount < condition.minActionCount) return false;

    // Condition 2: days since first launch
    final firstLaunchedStr = prefs.getString(_keyFirstLaunchedAt);
    if (firstLaunchedStr == null) return false;
    final firstLaunched = DateTime.tryParse(firstLaunchedStr);
    if (firstLaunched == null) return false;
    final daysSinceFirstLaunch = DateTime.now().difference(firstLaunched).inDays;
    if (daysSinceFirstLaunch < condition.minDaysFromFirstLaunch) return false;

    // Condition 3: request count limit
    final requestCount = prefs.getInt(_keyRequestCount) ?? 0;
    if (requestCount >= condition.maxRequestCount) return false;

    // All conditions met — request review
    final result = await _client.requestReview();

    // Record request (count regardless of success)
    await prefs.setInt(_keyRequestCount, requestCount + 1);

    onReviewRequested?.call(result);

    return result.success;
  }

  /// Reset all tracked state.
  ///
  /// Useful for testing or when the user re-installs. Clears
  /// first-launch date, action count, and request count.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyFirstLaunchedAt),
      prefs.remove(_keyActionCount),
      prefs.remove(_keyRequestCount),
    ]);
  }
}
