import 'dart:io' show Platform;

import 'messages.g.dart';

/// Thin wrapper around the native In-App Review API.
///
/// Provides a simple Dart interface to request in-app reviews
/// and open the store listing page. Does not manage any state
/// or conditions — use [ReviewController] for smart triggering.
///
/// ```dart
/// final client = AppReviewClient();
/// final result = await client.requestReview();
/// if (!result.success) {
///   // fallback: open store page
///   await client.openStoreListing(iosAppId: '123456789');
/// }
/// ```
class AppReviewClient {
  /// Creates an [AppReviewClient].
  ///
  /// Uses the Pigeon-generated [ReviewApi] to communicate with
  /// the native platform.
  AppReviewClient({ReviewApi? api}) : _api = api ?? ReviewApi();

  final ReviewApi _api;

  /// Request the native in-app review dialog.
  ///
  /// Returns a [ReviewResult] indicating whether the request was
  /// executed successfully. Note that even on success, the OS may
  /// choose not to display the dialog (quota limits).
  Future<ReviewResult> requestReview() => _api.requestReview();

  /// Open the app's store listing page.
  ///
  /// Use this as a fallback when the in-app review dialog cannot
  /// be shown, or when you want to direct users to the store.
  ///
  /// On iOS, [iosAppId] (the numeric App Store ID, e.g. "123456789")
  /// is sent to the native side. On Android, [androidPackageName] is
  /// sent; if null, the native side auto-detects the package name.
  ///
  /// Each parameter is only used on its respective platform, so
  /// specifying both is safe for cross-platform code.
  Future<ReviewResult> openStoreListing({String? iosAppId, String? androidPackageName}) {
    final appId = Platform.isIOS ? iosAppId : androidPackageName;
    return _api.openStoreListing(appId);
  }
}
