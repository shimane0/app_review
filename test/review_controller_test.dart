import 'package:app_review/app_review.dart';
import 'package:app_review/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [ReviewApi] for testing [ReviewController].
class FakeReviewApi extends ReviewApi {
  ReviewResult requestReviewResult = ReviewResult(success: true);
  ReviewResult openStoreListingResult = ReviewResult(success: true);

  int requestReviewCallCount = 0;
  int openStoreListingCallCount = 0;
  String? lastOpenStoreListingAppId;

  @override
  Future<ReviewResult> requestReview() async {
    requestReviewCallCount++;
    return requestReviewResult;
  }

  @override
  Future<ReviewResult> openStoreListing(String? appId) async {
    openStoreListingCallCount++;
    lastOpenStoreListingAppId = appId;
    return openStoreListingResult;
  }
}

void main() {
  late FakeReviewApi fakeApi;
  late InMemoryReviewStateStore store;

  setUp(() {
    fakeApi = FakeReviewApi();
    store = InMemoryReviewStateStore();
  });

  ReviewController createController({
    ReviewCondition condition = const ReviewCondition(),
    PrePromptCallback? prePrompt,
    void Function(ReviewResult)? onReviewRequested,
    void Function()? onNegativeFeedback,
    String? iosAppId,
    String? androidPackageName,
    bool fallbackToStoreListing = false,
  }) {
    return ReviewController(
      store: store,
      condition: condition,
      client: AppReviewClient(api: fakeApi),
      prePrompt: prePrompt,
      onReviewRequested: onReviewRequested,
      onNegativeFeedback: onNegativeFeedback,
      iosAppId: iosAppId,
      androidPackageName: androidPackageName,
      fallbackToStoreListing: fallbackToStoreListing,
    );
  }

  group('ReviewController', () {
    group('recordFirstLaunch', () {
      test('records first launch timestamp', () async {
        final controller = createController();

        await controller.recordFirstLaunch();

        final stored = await store.getFirstLaunchedAt();
        expect(stored, isNotNull);
      });

      test('does not overwrite existing first launch', () async {
        final controller = createController();

        await controller.recordFirstLaunch();
        final first = await store.getFirstLaunchedAt();

        await controller.recordFirstLaunch();
        final second = await store.getFirstLaunchedAt();

        expect(first, second);
      });
    });

    group('recordAction', () {
      test('increments action count', () async {
        final controller = createController();

        await controller.recordAction();
        expect(await store.getActionCount(), 1);

        await controller.recordAction();
        expect(await store.getActionCount(), 2);
      });
    });

    group('requestReviewIfEligible', () {
      /// Helper: set up store so all conditions are met.
      Future<void> makeEligible() async {
        // Action count >= 1 (default minActionCount)
        await store.setActionCount(5);
        // First launch 10 days ago (default minDaysFromFirstLaunch = 3)
        final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
        await store.setFirstLaunchedAt(tenDaysAgo);
        // Request count < 3 (default maxRequestCount)
        await store.setRequestCount(0);
      }

      test('returns conditionsNotMet when action count is insufficient', () async {
        final controller = createController();
        await store.setActionCount(0);

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.conditionsNotMet);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('returns conditionsNotMet when first launch not recorded', () async {
        final controller = createController();
        await store.setActionCount(5);

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.conditionsNotMet);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('returns conditionsNotMet when not enough days since first launch', () async {
        final controller = createController();
        await store.setActionCount(5);
        await store.setFirstLaunchedAt(DateTime.now()); // today = 0 days

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.conditionsNotMet);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('returns conditionsNotMet when request count limit reached', () async {
        final controller = createController();
        await makeEligible();
        await store.setRequestCount(3);

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.conditionsNotMet);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('returns reviewed when all conditions met (no pre-prompt)', () async {
        final controller = createController();
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.reviewed);
        expect(fakeApi.requestReviewCallCount, 1);
        expect(await store.getRequestCount(), 1);
      });

      test('returns reviewFailed on API failure', () async {
        fakeApi.requestReviewResult = ReviewResult(success: false, errorMessage: 'fail');
        final controller = createController();
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.reviewFailed);
        expect(await store.getRequestCount(), 1);
      });

      test('invokes onReviewRequested callback', () async {
        ReviewResult? callbackResult;
        final controller = createController(onReviewRequested: (r) => callbackResult = r);
        await makeEligible();

        await controller.requestReviewIfEligible();

        expect(callbackResult, isNotNull);
        expect(callbackResult!.success, isTrue);
      });

      test('returns conditionsNotMet when cooldown not elapsed', () async {
        final controller = createController(
          condition: const ReviewCondition(minHoursBetweenRequests: 720),
        );
        await makeEligible();
        // Last request was 1 hour ago (well within 720h cooldown)
        await store.setLastRequestedAt(DateTime.now().subtract(const Duration(hours: 1)));

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.conditionsNotMet);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('passes cooldown when enough time has elapsed', () async {
        final controller = createController(
          condition: const ReviewCondition(minHoursBetweenRequests: 24),
        );
        await makeEligible();
        await store.setLastRequestedAt(DateTime.now().subtract(const Duration(hours: 25)));

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.reviewed);
        expect(fakeApi.requestReviewCallCount, 1);
      });

      test('passes cooldown on first request (no lastRequestedAt)', () async {
        final controller = createController();
        await makeEligible();
        // No lastRequestedAt set — first time

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.reviewed);
      });

      test('records lastRequestedAt after successful request', () async {
        final controller = createController();
        await makeEligible();

        await controller.requestReviewIfEligible();

        final lastRequested = await store.getLastRequestedAt();
        expect(lastRequested, isNotNull);
        expect(DateTime.now().difference(lastRequested!).inSeconds, lessThan(2));
      });
    });

    group('prePrompt', () {
      Future<void> makeEligible() async {
        await store.setActionCount(5);
        final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
        await store.setFirstLaunchedAt(tenDaysAgo);
        await store.setRequestCount(0);
      }

      test('shows OS dialog when user responds positive', () async {
        final controller = createController(prePrompt: () async => PrePromptResponse.positive);
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.reviewed);
        expect(fakeApi.requestReviewCallCount, 1);
        expect(await store.getRequestCount(), 1);
      });

      test('returns negativeFromPrePrompt when user responds negative', () async {
        final controller = createController(prePrompt: () async => PrePromptResponse.negative);
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.negativeFromPrePrompt);
        expect(fakeApi.requestReviewCallCount, 0);
        expect(await store.getRequestCount(), 0);
      });

      test('invokes onNegativeFeedback when user responds negative', () async {
        var negativeCalled = false;
        final controller = createController(
          prePrompt: () async => PrePromptResponse.negative,
          onNegativeFeedback: () => negativeCalled = true,
        );
        await makeEligible();

        await controller.requestReviewIfEligible();

        expect(negativeCalled, isTrue);
      });

      test('returns dismissedFromPrePrompt when user dismisses', () async {
        final controller = createController(prePrompt: () async => PrePromptResponse.dismissed);
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.dismissedFromPrePrompt);
        expect(fakeApi.requestReviewCallCount, 0);
        expect(await store.getRequestCount(), 0);
      });

      test('does not show pre-prompt when conditions not met', () async {
        var prePromptCalled = false;
        final controller = createController(
          prePrompt: () async {
            prePromptCalled = true;
            return PrePromptResponse.positive;
          },
        );
        // Conditions not met (no actions)

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.conditionsNotMet);
        expect(prePromptCalled, isFalse);
      });
    });

    group('fallbackToStoreListing', () {
      Future<void> makeEligible() async {
        await store.setActionCount(5);
        final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
        await store.setFirstLaunchedAt(tenDaysAgo);
        await store.setRequestCount(0);
      }

      test('opens store listing when review fails and fallback enabled', () async {
        fakeApi.requestReviewResult = ReviewResult(success: false, errorMessage: 'fail');
        fakeApi.openStoreListingResult = ReviewResult(success: true);

        final controller = createController(iosAppId: '123456789', fallbackToStoreListing: true);
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, ReviewRequestResult.reviewed);
        expect(fakeApi.requestReviewCallCount, 1);
        expect(fakeApi.openStoreListingCallCount, 1);
      });

      test('does not open store listing when review succeeds', () async {
        final controller = createController(iosAppId: '123456789', fallbackToStoreListing: true);
        await makeEligible();

        await controller.requestReviewIfEligible();

        expect(fakeApi.openStoreListingCallCount, 0);
      });

      test('does not open store listing when fallback disabled', () async {
        fakeApi.requestReviewResult = ReviewResult(success: false, errorMessage: 'fail');

        final controller = createController();
        await makeEligible();

        await controller.requestReviewIfEligible();

        expect(fakeApi.openStoreListingCallCount, 0);
      });
    });

    group('reset', () {
      test('clears all tracked state', () async {
        final controller = createController();

        await controller.recordFirstLaunch();
        await controller.recordAction();
        await store.setLastRequestedAt(DateTime.now());
        await controller.reset();

        expect(await store.getFirstLaunchedAt(), isNull);
        expect(await store.getActionCount(), 0);
        expect(await store.getRequestCount(), 0);
        expect(await store.getLastRequestedAt(), isNull);
      });
    });

    group('getStatus', () {
      test('returns initial status with zero counts', () async {
        final controller = createController();

        final status = await controller.getStatus();

        expect(status.actionCount, 0);
        expect(status.requestCount, 0);
        expect(status.firstLaunchedAt, isNull);
        expect(status.daysSinceFirstLaunch, isNull);
      });

      test('reflects recorded actions and first launch', () async {
        final controller = createController();

        await controller.recordFirstLaunch();
        await controller.recordAction();
        await controller.recordAction();

        final status = await controller.getStatus();

        expect(status.actionCount, 2);
        expect(status.requestCount, 0);
        expect(status.firstLaunchedAt, isNotNull);
        expect(status.daysSinceFirstLaunch, 0);
      });

      test('includes condition thresholds', () async {
        final controller = createController(
          condition: const ReviewCondition(
            minActionCount: 5,
            minDaysFromFirstLaunch: 7,
            maxRequestCount: 2,
          ),
        );

        final status = await controller.getStatus();

        expect(status.condition.minActionCount, 5);
        expect(status.condition.minDaysFromFirstLaunch, 7);
        expect(status.condition.maxRequestCount, 2);
      });

      test('returns lastRequestedAt in status', () async {
        final controller = createController();
        final now = DateTime.now();
        await store.setLastRequestedAt(now);

        final status = await controller.getStatus();

        expect(status.lastRequestedAt, now);
      });

      test('returns null hoursSinceLastRequest when never requested', () async {
        final controller = createController();

        final status = await controller.getStatus();

        expect(status.lastRequestedAt, isNull);
        expect(status.hoursSinceLastRequest, isNull);
      });

      test('calculates hoursSinceLastRequest correctly', () async {
        final controller = createController();
        await store.setLastRequestedAt(DateTime.now().subtract(const Duration(hours: 48)));

        final status = await controller.getStatus();

        expect(status.hoursSinceLastRequest, 48);
      });

      test('default minHoursBetweenRequests is 720', () {
        const condition = ReviewCondition();
        expect(condition.minHoursBetweenRequests, 720);
      });
    });

    group('forceRequestReview', () {
      test('requests review without checking conditions', () async {
        final controller = createController();
        // No actions, no first launch — conditions NOT met

        final result = await controller.forceRequestReview();

        expect(result.success, isTrue);
        expect(fakeApi.requestReviewCallCount, 1);
      });

      test('does not increment request count', () async {
        final controller = createController();

        await controller.forceRequestReview();
        await controller.forceRequestReview();

        expect(await store.getRequestCount(), 0);
      });

      test('invokes onReviewRequested callback', () async {
        ReviewResult? callbackResult;
        final controller = createController(onReviewRequested: (r) => callbackResult = r);

        await controller.forceRequestReview();

        expect(callbackResult, isNotNull);
        expect(callbackResult!.success, isTrue);
      });

      test('returns failure result on API error', () async {
        fakeApi.requestReviewResult = ReviewResult(success: false, errorMessage: 'not available');
        final controller = createController();

        final result = await controller.forceRequestReview();

        expect(result.success, isFalse);
        expect(result.errorMessage, 'not available');
      });
    });

    group('forceRequestReviewWithPrePrompt', () {
      test('shows pre-prompt and requests review on positive', () async {
        final controller = createController(prePrompt: () async => PrePromptResponse.positive);

        final result = await controller.forceRequestReviewWithPrePrompt();

        expect(result, ReviewRequestResult.reviewed);
        expect(fakeApi.requestReviewCallCount, 1);
      });

      test('returns negativeFromPrePrompt on negative', () async {
        var negativeCalled = false;
        final controller = createController(
          prePrompt: () async => PrePromptResponse.negative,
          onNegativeFeedback: () => negativeCalled = true,
        );

        final result = await controller.forceRequestReviewWithPrePrompt();

        expect(result, ReviewRequestResult.negativeFromPrePrompt);
        expect(fakeApi.requestReviewCallCount, 0);
        expect(negativeCalled, isTrue);
      });

      test('returns dismissedFromPrePrompt on dismissed', () async {
        final controller = createController(prePrompt: () async => PrePromptResponse.dismissed);

        final result = await controller.forceRequestReviewWithPrePrompt();

        expect(result, ReviewRequestResult.dismissedFromPrePrompt);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('does not increment request count', () async {
        final controller = createController(prePrompt: () async => PrePromptResponse.positive);

        await controller.forceRequestReviewWithPrePrompt();

        expect(await store.getRequestCount(), 0);
      });

      test('without prePrompt behaves like forceRequestReview', () async {
        final controller = createController();

        final result = await controller.forceRequestReviewWithPrePrompt();

        expect(result, ReviewRequestResult.reviewed);
        expect(fakeApi.requestReviewCallCount, 1);
      });

      test('returns reviewFailed on API error after positive', () async {
        fakeApi.requestReviewResult = ReviewResult(success: false, errorMessage: 'error');
        final controller = createController(prePrompt: () async => PrePromptResponse.positive);

        final result = await controller.forceRequestReviewWithPrePrompt();

        expect(result, ReviewRequestResult.reviewFailed);
      });

      test('invokes onReviewRequested callback on positive', () async {
        ReviewResult? callbackResult;
        final controller = createController(
          prePrompt: () async => PrePromptResponse.positive,
          onReviewRequested: (r) => callbackResult = r,
        );

        await controller.forceRequestReviewWithPrePrompt();

        expect(callbackResult, isNotNull);
        expect(callbackResult!.success, isTrue);
      });
    });
  });
}
