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
  /// - [iosAppId]: The numeric App Store ID (e.g. "123456789").
  ///   Required on iOS. On Android this is ignored and the
  ///   package name is auto-detected.
  /// - [androidPackageName]: The Android package name. If null,
  ///   the current app's package name is used automatically.
  Future<ReviewResult> openStoreListing({String? iosAppId, String? androidPackageName}) {
    // The native side handles appId per platform:
    // - Android: uses it as package name (or auto-detects if null)
    // - iOS: uses it as App Store numeric ID
    return _api.openStoreListing(iosAppId ?? androidPackageName);
  }
}
