import 'app_review_client.dart';
import 'messages.g.dart';
import 'review_state_store.dart';

/// User response to a pre-prompt question.
///
/// Returned by [PrePromptCallback] to determine next steps:
/// - [positive]: The user is happy — show the OS review dialog.
/// - [negative]: The user wants to give feedback — invoke
///   [ReviewController.onNegativeFeedback] if set.
/// - [dismissed]: The user closed the prompt without choosing.
enum PrePromptResponse { positive, negative, dismissed }

/// Callback that shows a pre-prompt UI and returns the user's
/// response.
///
/// The app is responsible for building and displaying the UI
/// (e.g. a BottomSheet or Dialog). This callback only needs to
/// return the user's choice.
typedef PrePromptCallback = Future<PrePromptResponse> Function();

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
    required this.lastRequestedAt,
    required this.condition,
  });

  /// Number of recorded user actions.
  final int actionCount;

  /// Number of review requests already made.
  final int requestCount;

  /// Timestamp of the first recorded launch, or `null`
  /// if [ReviewController.recordFirstLaunch] was never called.
  final DateTime? firstLaunchedAt;

  /// Timestamp of the last review request, or `null`
  /// if no review has been requested yet.
  final DateTime? lastRequestedAt;

  /// The condition thresholds being used.
  final ReviewCondition condition;

  /// Days elapsed since first launch, or `null` if not recorded.
  int? get daysSinceFirstLaunch {
    if (firstLaunchedAt == null) return null;
    return DateTime.now().difference(firstLaunchedAt!).inDays;
  }

  /// Hours elapsed since the last review request, or `null`
  /// if no review has been requested yet.
  int? get hoursSinceLastRequest {
    if (lastRequestedAt == null) return null;
    return DateTime.now().difference(lastRequestedAt!).inHours;
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
    this.minHoursBetweenRequests = 720,
  });

  /// Minimum days since the first recorded launch before
  /// a review request is eligible.
  final int minDaysFromFirstLaunch;

  /// Minimum number of recorded user actions (e.g. shares,
  /// completions) before a review request is eligible.
  final int minActionCount;

  /// Maximum number of review requests the app will make.
  /// After this limit, [ReviewController.requestReviewIfEligible]
  /// always returns [ReviewRequestResult.conditionsNotMet]
  /// without calling the native API.
  final int maxRequestCount;

  /// Minimum hours between review requests (cooldown).
  ///
  /// Defaults to 720 hours (30 days). Prevents requesting
  /// reviews too frequently, complementing the OS-level
  /// throttling with an app-side cooldown.
  final int minHoursBetweenRequests;
}

/// Result of [ReviewController.requestReviewIfEligible].
///
/// Indicates what happened during the review request flow,
/// including whether a pre-prompt was shown and how the user
/// responded.
enum ReviewRequestResult {
  /// Conditions were not met; nothing was shown.
  conditionsNotMet,

  /// The pre-prompt was shown and the user chose "negative".
  negativeFromPrePrompt,

  /// The pre-prompt was shown and the user dismissed it.
  dismissedFromPrePrompt,

  /// The OS review dialog was requested successfully.
  reviewed,

  /// The OS review dialog request failed (and fallback, if
  /// enabled, also failed or was not configured).
  reviewFailed,
}

/// Smart review request controller with condition management.
///
/// Tracks user activity and first-launch date via a
/// [ReviewStateStore], and requests a review only when all
/// configured conditions are met.
///
/// Supports an optional [prePrompt] callback that shows a
/// custom UI before the OS review dialog. This lets the app
/// filter out unhappy users and avoid wasting the limited
/// OS-level review quota.
///
/// ```dart
/// final controller = ReviewController(
///   store: myStore,
///   condition: const ReviewCondition(
///     minDaysFromFirstLaunch: 3,
///     minActionCount: 1,
///     maxRequestCount: 3,
///   ),
///   prePrompt: () => showMyPrePromptDialog(),
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
/// // Check conditions, show pre-prompt, then request review
/// final result = await controller.requestReviewIfEligible();
/// ```
class ReviewController {
  /// Creates a [ReviewController].
  ///
  /// - [store]: The storage backend for review state. Use
  ///   [InMemoryReviewStateStore] for tests; provide your own
  ///   implementation (e.g. SharedPreferences-backed) in the app.
  /// - [condition]: The conditions that must be met.
  /// - [client]: An [AppReviewClient] instance. If null,
  ///   a default instance is created.
  /// - [prePrompt]: Optional callback that shows a pre-prompt
  ///   UI and returns the user's response. When set, the OS
  ///   review dialog is only shown if the user responds
  ///   [PrePromptResponse.positive]. When null, the OS dialog
  ///   is shown directly (legacy behaviour).
  /// - [onReviewRequested]: Optional callback invoked after
  ///   a review is requested, with the [ReviewResult].
  ///   Useful for analytics logging.
  /// - [onNegativeFeedback]: Optional callback invoked when
  ///   the user responds [PrePromptResponse.negative] to the
  ///   pre-prompt. The app can use this to open a feedback
  ///   form, email, etc.
  /// - [iosAppId]: The numeric App Store ID (e.g. "123456789").
  ///   Used when [fallbackToStoreListing] is `true` on iOS.
  /// - [androidPackageName]: The Android package name. If null,
  ///   the native side auto-detects it. Used when
  ///   [fallbackToStoreListing] is `true` on Android.
  /// - [fallbackToStoreListing]: When `true`, if the in-app
  ///   review dialog fails, the store listing page is opened
  ///   automatically as a fallback.
  ReviewController({
    required ReviewStateStore store,
    this.condition = const ReviewCondition(),
    AppReviewClient? client,
    this.prePrompt,
    this.onReviewRequested,
    this.onNegativeFeedback,
    this.iosAppId,
    this.androidPackageName,
    this.fallbackToStoreListing = false,
  }) : _store = store,
       _client = client ?? AppReviewClient();

  /// The conditions that must all be met for a review request.
  final ReviewCondition condition;

  final ReviewStateStore _store;
  final AppReviewClient _client;

  /// Optional pre-prompt callback. When set, the OS review
  /// dialog is shown only if the user responds positively.
  final PrePromptCallback? prePrompt;

  /// Optional callback invoked after a review request completes.
  final void Function(ReviewResult result)? onReviewRequested;

  /// Optional callback invoked when the user responds negatively
  /// to the pre-prompt.
  final void Function()? onNegativeFeedback;

  /// The numeric App Store ID for iOS store listing fallback.
  final String? iosAppId;

  /// The Android package name for store listing fallback.
  /// If null, the native side auto-detects the package name.
  final String? androidPackageName;

  /// Whether to open the store listing page when the in-app
  /// review dialog fails.
  final bool fallbackToStoreListing;

  /// Record the app's first launch timestamp.
  ///
  /// Call this once during app initialization. If already
  /// recorded, this is a no-op.
  Future<void> recordFirstLaunch() async {
    final existing = await _store.getFirstLaunchedAt();
    if (existing != null) return;
    await _store.setFirstLaunchedAt(DateTime.now());
  }

  /// Record a user action (e.g. share, save, complete).
  ///
  /// Increments the internal action counter used for
  /// eligibility checking.
  Future<void> recordAction() async {
    final current = await _store.getActionCount();
    await _store.setActionCount(current + 1);
  }

  /// Check all conditions and request a review if eligible.
  ///
  /// When [prePrompt] is set, the flow is:
  /// 1. Check conditions → return [ReviewRequestResult.conditionsNotMet]
  ///    if any condition fails.
  /// 2. Show the pre-prompt → branch on the user's response.
  /// 3. If [PrePromptResponse.positive], show the OS dialog.
  /// 4. If [PrePromptResponse.negative], call
  ///    [onNegativeFeedback] and return
  ///    [ReviewRequestResult.negativeFromPrePrompt].
  /// 5. If [PrePromptResponse.dismissed], return
  ///    [ReviewRequestResult.dismissedFromPrePrompt].
  ///
  /// When [prePrompt] is null, the OS dialog is shown directly
  /// after conditions pass (legacy behaviour).
  ///
  /// The request count is only incremented when the OS dialog
  /// is actually requested (step 3 or legacy).
  ///
  /// The cooldown timestamp ([ReviewStateStore.setLastRequestedAt])
  /// is updated on **any** path where the pre-prompt is shown
  /// (positive/negative/dismissed). This ensures the pre-prompt
  /// is not shown again within [ReviewCondition.minHoursBetweenRequests]
  /// regardless of the user's response.
  Future<ReviewRequestResult> requestReviewIfEligible() async {
    // Condition 1: action count
    final actionCount = await _store.getActionCount();
    if (actionCount < condition.minActionCount) {
      return ReviewRequestResult.conditionsNotMet;
    }

    // Condition 2: days since first launch
    final firstLaunched = await _store.getFirstLaunchedAt();
    if (firstLaunched == null) {
      return ReviewRequestResult.conditionsNotMet;
    }
    final daysSinceFirstLaunch = DateTime.now().difference(firstLaunched).inDays;
    if (daysSinceFirstLaunch < condition.minDaysFromFirstLaunch) {
      return ReviewRequestResult.conditionsNotMet;
    }

    // Condition 3: request count limit
    final requestCount = await _store.getRequestCount();
    if (requestCount >= condition.maxRequestCount) {
      return ReviewRequestResult.conditionsNotMet;
    }

    // Condition 4: cooldown since last request
    final lastRequested = await _store.getLastRequestedAt();
    if (lastRequested != null) {
      final hoursSince = DateTime.now().difference(lastRequested).inHours;
      if (hoursSince < condition.minHoursBetweenRequests) {
        return ReviewRequestResult.conditionsNotMet;
      }
    }

    // Pre-prompt (if configured)
    if (prePrompt != null) {
      final response = await prePrompt!();
      switch (response) {
        case PrePromptResponse.negative:
          // Record prompt shown time so the cooldown applies even
          // when the user declines — this prevents the pre-prompt
          // from being shown again on every subsequent action.
          await _store.setLastRequestedAt(DateTime.now());
          onNegativeFeedback?.call();
          return ReviewRequestResult.negativeFromPrePrompt;
        case PrePromptResponse.dismissed:
          // Record prompt shown time so the cooldown applies even
          // when the user dismisses — without this the pre-prompt
          // would reappear on every subsequent action.
          await _store.setLastRequestedAt(DateTime.now());
          return ReviewRequestResult.dismissedFromPrePrompt;
        case PrePromptResponse.positive:
          break; // Continue to OS dialog
      }
    }

    // Request OS review dialog
    return _requestReview(requestCount);
  }

  /// Reset all tracked state.
  ///
  /// Clears first-launch date, action count, and request count.
  /// Useful for debug/preview UIs and tests.
  Future<void> reset() async {
    await _store.clear();
  }

  /// Get the current review tracking status.
  ///
  /// Returns a [ReviewStatus] snapshot containing the current
  /// action count, request count, first-launch timestamp, and
  /// the configured conditions.
  Future<ReviewStatus> getStatus() async {
    final actionCount = await _store.getActionCount();
    final requestCount = await _store.getRequestCount();
    final firstLaunchedAt = await _store.getFirstLaunchedAt();
    final lastRequestedAt = await _store.getLastRequestedAt();
    return ReviewStatus(
      actionCount: actionCount,
      requestCount: requestCount,
      firstLaunchedAt: firstLaunchedAt,
      lastRequestedAt: lastRequestedAt,
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

  /// Request an in-app review with pre-prompt, bypassing
  /// all conditions.
  ///
  /// Like [forceRequestReview], but exercises the full pre-prompt
  /// flow. Intended for debug/preview UIs and tests to verify
  /// that the pre-prompt UI works correctly before the OS dialog.
  /// Does **not** increment the request counter.
  ///
  /// When [prePrompt] is null, behaves identically to
  /// [forceRequestReview].
  Future<ReviewRequestResult> forceRequestReviewWithPrePrompt() async {
    if (prePrompt != null) {
      final response = await prePrompt!();
      switch (response) {
        case PrePromptResponse.negative:
          onNegativeFeedback?.call();
          return ReviewRequestResult.negativeFromPrePrompt;
        case PrePromptResponse.dismissed:
          return ReviewRequestResult.dismissedFromPrePrompt;
        case PrePromptResponse.positive:
          break;
      }
    }
    final result = await _client.requestReview();
    onReviewRequested?.call(result);
    return result.success ? ReviewRequestResult.reviewed : ReviewRequestResult.reviewFailed;
  }

  /// Internal: request the OS dialog and handle fallback.
  Future<ReviewRequestResult> _requestReview(int currentRequestCount) async {
    var result = await _client.requestReview();

    // Fallback to store listing on failure
    if (!result.success && fallbackToStoreListing) {
      result = await _client.openStoreListing(
        iosAppId: iosAppId,
        androidPackageName: androidPackageName,
      );
    }

    // Record request (count regardless of success)
    await _store.setRequestCount(currentRequestCount + 1);
    await _store.setLastRequestedAt(DateTime.now());

    onReviewRequested?.call(result);

    return result.success ? ReviewRequestResult.reviewed : ReviewRequestResult.reviewFailed;
  }
}
