import Flutter
import StoreKit
import UIKit

/// Flutter Plugin for In-App Review.
///
/// Implements `ReviewApi` using StoreKit `SKStoreReviewController`.
/// Automatically registers via Flutter's plugin system.
public class AppReviewPlugin: NSObject, FlutterPlugin, ReviewApi {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AppReviewPlugin()
        ReviewApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    // MARK: - ReviewApi

    func requestReview(completion: @escaping (Result<ReviewResult, Error>) -> Void) {
        DispatchQueue.main.async {
            if let windowScene = self.currentWindowScene() {
                SKStoreReviewController.requestReview(in: windowScene)
                completion(.success(ReviewResult(success: true)))
            } else {
                completion(.success(ReviewResult(
                    success: false,
                    errorMessage: "Window scene is not available"
                )))
            }
        }
    }

    func openStoreListing(appId: String?, completion: @escaping (Result<ReviewResult, Error>) -> Void) {
        let storeId = appId ?? Bundle.main.bundleIdentifier ?? ""

        // Use numeric App Store ID if provided, otherwise fall back to bundle ID URL
        let urlString: String
        if let appId = appId, !appId.isEmpty {
            urlString = "https://apps.apple.com/app/id\(appId)"
        } else {
            urlString = "https://apps.apple.com/app/\(storeId)"
        }

        guard let url = URL(string: urlString) else {
            completion(.success(ReviewResult(
                success: false,
                errorMessage: "Failed to build store URL"
            )))
            return
        }

        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    completion(.success(ReviewResult(success: true)))
                } else {
                    completion(.success(ReviewResult(
                        success: false,
                        errorMessage: "Could not open store listing"
                    )))
                }
            }
        }
    }

    // MARK: - Private

    private func currentWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
