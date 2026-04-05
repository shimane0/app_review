import 'package:app_review/app_review.dart';
import 'package:app_review/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  late SharedPreferences prefs;

  setUp(() async {
    fakeApi = FakeReviewApi();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ReviewController createController({
    ReviewCondition condition = const ReviewCondition(),
    void Function(ReviewResult)? onReviewRequested,
    String? iosAppId,
    String? androidPackageName,
    bool fallbackToStoreListing = false,
  }) {
    return ReviewController(
      condition: condition,
      client: AppReviewClient(api: fakeApi),
      prefs: prefs,
      onReviewRequested: onReviewRequested,
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

        final stored = prefs.getString('app_review_first_launched_at');
        expect(stored, isNotNull);
        expect(DateTime.tryParse(stored!), isNotNull);
      });

      test('does not overwrite existing first launch', () async {
        final controller = createController();

        await controller.recordFirstLaunch();
        final first = prefs.getString('app_review_first_launched_at');

        await controller.recordFirstLaunch();
        final second = prefs.getString('app_review_first_launched_at');

        expect(first, second);
      });
    });

    group('recordAction', () {
      test('increments action count', () async {
        final controller = createController();

        await controller.recordAction();
        expect(prefs.getInt('app_review_action_count'), 1);

        await controller.recordAction();
        expect(prefs.getInt('app_review_action_count'), 2);
      });
    });

    group('requestReviewIfEligible', () {
      /// Helper: set up prefs so all conditions are met.
      Future<void> makeEligible() async {
        // Action count >= 1 (default minActionCount)
        await prefs.setInt('app_review_action_count', 5);
        // First launch 10 days ago (default minDaysFromFirstLaunch = 3)
        final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
        await prefs.setString(
          'app_review_first_launched_at',
          tenDaysAgo.toIso8601String(),
        );
        // Request count < 3 (default maxRequestCount)
        await prefs.setInt('app_review_request_count', 0);
      }

      test('returns false when action count is insufficient', () async {
        final controller = createController();
        await prefs.setInt('app_review_action_count', 0);

        final result = await controller.requestReviewIfEligible();

        expect(result, isFalse);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('returns false when first launch not recorded', () async {
        final controller = createController();
        await prefs.setInt('app_review_action_count', 5);

        final result = await controller.requestReviewIfEligible();

        expect(result, isFalse);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('returns false when not enough days since first launch', () async {
        final controller = createController();
        await prefs.setInt('app_review_action_count', 5);
        await prefs.setString(
          'app_review_first_launched_at',
          DateTime.now().toIso8601String(), // today = 0 days
        );

        final result = await controller.requestReviewIfEligible();

        expect(result, isFalse);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('returns false when request count limit reached', () async {
        final controller = createController();
        await makeEligible();
        await prefs.setInt('app_review_request_count', 3);

        final result = await controller.requestReviewIfEligible();

        expect(result, isFalse);
        expect(fakeApi.requestReviewCallCount, 0);
      });

      test('requests review when all conditions met', () async {
        final controller = createController();
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, isTrue);
        expect(fakeApi.requestReviewCallCount, 1);
        expect(prefs.getInt('app_review_request_count'), 1);
      });

      test('increments request count even on failure', () async {
        fakeApi.requestReviewResult = ReviewResult(
          success: false,
          errorMessage: 'fail',
        );
        final controller = createController();
        await makeEligible();

        final result = await controller.requestReviewIfEligible();

        expect(result, isFalse);
        expect(prefs.getInt('app_review_request_count'), 1);
      });

      test('invokes onReviewRequested callback', () async {
        ReviewResult? callbackResult;
        final controller = createController(
          onReviewRequested: (r) => callbackResult = r,
        );
        await makeEligible();

        await controller.requestReviewIfEligible();

        expect(callbackResult, isNotNull);
        expect(callbackResult!.success, isTrue);
      });
    });

    group('fallbackToStoreListing', () {
      Future<void> makeEligible() async {
        await prefs.setInt('app_review_action_count', 5);
        final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
        await prefs.setString(
          'app_review_first_launched_at',
          tenDaysAgo.toIso8601String(),
        );
        await prefs.setInt('app_review_request_count', 0);
      }

      test(
        'opens store listing when review fails and fallback enabled',
        () async {
          fakeApi.requestReviewResult = ReviewResult(
            success: false,
            errorMessage: 'fail',
          );
          fakeApi.openStoreListingResult = ReviewResult(success: true);

          final controller = createController(
            iosAppId: '123456789',
            fallbackToStoreListing: true,
          );
          await makeEligible();

          final result = await controller.requestReviewIfEligible();

          expect(result, isTrue);
          expect(fakeApi.requestReviewCallCount, 1);
          expect(fakeApi.openStoreListingCallCount, 1);
        },
      );

      test('does not open store listing when review succeeds', () async {
        final controller = createController(
          iosAppId: '123456789',
          fallbackToStoreListing: true,
        );
        await makeEligible();

        await controller.requestReviewIfEligible();

        expect(fakeApi.openStoreListingCallCount, 0);
      });

      test('does not open store listing when fallback disabled', () async {
        fakeApi.requestReviewResult = ReviewResult(
          success: false,
          errorMessage: 'fail',
        );

        final controller = createController(fallbackToStoreListing: false);
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
        // ignore: invalid_use_of_visible_for_testing_member
        await controller.reset();

        expect(prefs.getString('app_review_first_launched_at'), isNull);
        expect(prefs.getInt('app_review_action_count'), isNull);
        expect(prefs.getInt('app_review_request_count'), isNull);
      });
    });
  });
}
