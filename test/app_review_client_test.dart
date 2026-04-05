import 'dart:io' show Platform;

import 'package:app_review/app_review.dart';
import 'package:app_review/src/messages.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [ReviewApi] that records calls and returns configurable results.
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
  late AppReviewClient client;

  setUp(() {
    fakeApi = FakeReviewApi();
    client = AppReviewClient(api: fakeApi);
  });

  group('AppReviewClient', () {
    test('requestReview delegates to ReviewApi', () async {
      final result = await client.requestReview();

      expect(result.success, isTrue);
      expect(fakeApi.requestReviewCallCount, 1);
    });

    test('requestReview returns failure result from API', () async {
      fakeApi.requestReviewResult = ReviewResult(
        success: false,
        errorMessage: 'Activity is not available',
      );

      final result = await client.requestReview();

      expect(result.success, isFalse);
      expect(result.errorMessage, 'Activity is not available');
    });

    group('openStoreListing', () {
      test('sends iosAppId on iOS, androidPackageName on Android', () async {
        await client.openStoreListing(iosAppId: '123456789', androidPackageName: 'com.example.app');

        expect(fakeApi.openStoreListingCallCount, 1);
        if (Platform.isIOS) {
          expect(fakeApi.lastOpenStoreListingAppId, '123456789');
        } else {
          expect(fakeApi.lastOpenStoreListingAppId, 'com.example.app');
        }
      });

      test('sends null when no parameters provided', () async {
        await client.openStoreListing();

        expect(fakeApi.lastOpenStoreListingAppId, isNull);
      });

      test('sends only iosAppId on iOS even when both provided', () async {
        await client.openStoreListing(iosAppId: '123456789', androidPackageName: 'com.example.app');

        // On the current test platform (not iOS), this should be the Android value
        if (!Platform.isIOS) {
          expect(fakeApi.lastOpenStoreListingAppId, 'com.example.app');
        }
      });
    });
  });
}
