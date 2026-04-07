import 'package:shared_preferences/shared_preferences.dart';

import 'app_review_client.dart';
import 'messages.g.dart';

/// Snapshot of the review tracking state.
///
/// Returned by [ReviewController.getStatus] for display
/// in debug/preview UIs.
class ReviewStatus {
  /// Creates a [ReviewStatus].
  const ReviewStatus({
    required this.actionCount,
    required this.requestCount,
    required this.firstLaunchedAt,
    required this.condition,
  });

  /// Number of recorded user actions.
  final int actionCount;

  /// Number of review requests already made.
  final int requestCount;

  /// Timestamp of the first recorded launch, or `null`
  /// if [ReviewController.recordFirstLaunch] was never called.
  final DateTime? firstLaunchedAt;

  /// The condition thresholds being used.
  final ReviewCondition condition;

  /// Days elapsed since first launch, or `null` if not recorded.
  int? get daysSinceFirstLaunch {
    if (firstLaunchedAt == null) return null;
    return DateTime.now().difference(firstLaunchedAt!).inDays;
  }
}

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
///   iosAppId: '123456789',
///   fallbackToStoreListing: true,
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
  /// - [prefs]: A [SharedPreferences] instance for persistence.
  ///   If null, [SharedPreferences.getInstance()] is used lazily.
  ///   Passing an instance explicitly improves testability.
  /// - [onReviewRequested]: Optional callback invoked after
  ///   a review is requested, with the [ReviewResult].
  ///   Useful for analytics logging.
  /// - [iosAppId]: The numeric App Store ID (e.g. "123456789").
  ///   Used when [fallbackToStoreListing] is `true` on iOS.
  /// - [androidPackageName]: The Android package name. If null,
  ///   the native side auto-detects it. Used when
  ///   [fallbackToStoreListing] is `true` on Android.
  /// - [fallbackToStoreListing]: When `true`, if the in-app
  ///   review dialog fails, the store listing page is opened
  ///   automatically as a fallback.
  ReviewController({
    this.condition = const ReviewCondition(),
    AppReviewClient? client,
    SharedPreferences? prefs,
    this.onReviewRequested,
    this.iosAppId,
    this.androidPackageName,
    this.fallbackToStoreListing = false,
  }) : _client = client ?? AppReviewClient(),
       _prefs = prefs;

  /// The conditions that must all be met for a review request.
  final ReviewCondition condition;

  final AppReviewClient _client;

  SharedPreferences? _prefs;

  /// Optional callback invoked after a review request completes.
  final void Function(ReviewResult result)? onReviewRequested;

  /// The numeric App Store ID for iOS store listing fallback.
  final String? iosAppId;

  /// The Android package name for store listing fallback.
  /// If null, the native side auto-detects the package name.
  final String? androidPackageName;

  /// Whether to open the store listing page when the in-app
  /// review dialog fails.
  final bool fallbackToStoreListing;

  // SharedPreferences keys
  static const _keyFirstLaunchedAt = 'app_review_first_launched_at';
  static const _keyActionCount = 'app_review_action_count';
  static const _keyRequestCount = 'app_review_request_count';

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Record the app's first launch timestamp.
  ///
  /// Call this once during app initialization. If already
  /// recorded, this is a no-op.
  Future<void> recordFirstLaunch() async {
    final prefs = await _getPrefs();
    if (prefs.getString(_keyFirstLaunchedAt) != null) return;
    await prefs.setString(_keyFirstLaunchedAt, DateTime.now().toIso8601String());
  }

  /// Record a user action (e.g. share, save, complete).
  ///
  /// Increments the internal action counter used for
  /// eligibility checking.
  Future<void> recordAction() async {
    final prefs = await _getPrefs();
    final current = prefs.getInt(_keyActionCount) ?? 0;
    await prefs.setInt(_keyActionCount, current + 1);
  }

  /// Check all conditions and request a review if eligible.
  ///
  /// Returns `true` if a review request was actually made
  /// (regardless of whether the OS showed the dialog).
  ///
  /// When [fallbackToStoreListing] is `true` and the review
  /// dialog request fails, the store listing page is opened
  /// automatically as a fallback.
  ///
  /// Returns `false` if any condition was not met or the
  /// request (and fallback, if enabled) failed.
  Future<bool> requestReviewIfEligible() async {
    final prefs = await _getPrefs();

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
    var result = await _client.requestReview();

    // Fallback to store listing on failure
    if (!result.success && fallbackToStoreListing) {
      result = await _client.openStoreListing(
        iosAppId: iosAppId,
        androidPackageName: androidPackageName,
      );
    }

    // Record request (count regardless of success)
    await prefs.setInt(_keyRequestCount, requestCount + 1);

    onReviewRequested?.call(result);

    return result.success;
  }

  /// Reset all tracked state.
  ///
  /// Clears first-launch date, action count, and request count.
  /// Useful for debug/preview UIs and tests.
  Future<void> reset() async {
    final prefs = await _getPrefs();
    await Future.wait([
      prefs.remove(_keyFirstLaunchedAt),
      prefs.remove(_keyActionCount),
      prefs.remove(_keyRequestCount),
    ]);
  }

  /// Get the current review tracking status.
  ///
  /// Returns a [ReviewStatus] snapshot containing the current
  /// action count, request count, first-launch timestamp, and
  /// the configured conditions.
  Future<ReviewStatus> getStatus() async {
    final prefs = await _getPrefs();
    final actionCount = prefs.getInt(_keyActionCount) ?? 0;
    final requestCount = prefs.getInt(_keyRequestCount) ?? 0;
    final firstLaunchedStr = prefs.getString(_keyFirstLaunchedAt);
    final firstLaunchedAt = firstLaunchedStr != null ? DateTime.tryParse(firstLaunchedStr) : null;
    return ReviewStatus(
      actionCount: actionCount,
      requestCount: requestCount,
      firstLaunchedAt: firstLaunchedAt,
      condition: condition,
    );
  }

  /// Request an in-app review bypassing all conditions.
  ///
  /// Intended for debug/preview UIs to verify that the native
  /// review dialog can be displayed. Does **not** increment the
  /// request counter.
  Future<ReviewResult> forceRequestReview() async {
    final result = await _client.requestReview();
    onReviewRequested?.call(result);
    return result;
  }
}
