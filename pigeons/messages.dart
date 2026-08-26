import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'app_review',
    kotlinOut: 'android/src/main/kotlin/com/ochipan/app_review/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.ochipan.app_review'),
    swiftOut: 'ios/app_review/Sources/app_review/Messages.g.swift',
  ),
)
/// Result of a review request operation.
class ReviewResult {
  ReviewResult({required this.success, this.errorMessage});

  /// Whether the request was executed successfully.
  ///
  /// - Android: `true` when `launchReviewFlow` completes.
  ///   Whether the review dialog was actually shown or a review
  ///   was submitted cannot be determined.
  /// - iOS: `true` when `requestReview` was called.
  ///   Whether the OS shows the dialog is not controllable.
  final bool success;

  /// Error message on failure.
  final String? errorMessage;
}

/// Native In-App Review API.
///
/// Android: Google Play In-App Review API (review-ktx)
/// iOS: StoreKit SKStoreReviewController
@HostApi()
abstract class ReviewApi {
  /// Request the in-app review dialog.
  ///
  /// The OS decides whether to actually display the dialog.
  /// Both Android and iOS enforce their own display quotas.
  @async
  ReviewResult requestReview();

  /// Open the app's store listing page (fallback).
  ///
  /// When the review dialog cannot be shown, this opens
  /// the store page directly so the user can leave a review.
  /// [appId] is the platform-specific app identifier:
  /// - Android: package name (e.g. "com.example.app"), or null to auto-detect
  /// - iOS: numeric App Store ID (e.g. "123456789")
  @async
  ReviewResult openStoreListing(String? appId);
}
