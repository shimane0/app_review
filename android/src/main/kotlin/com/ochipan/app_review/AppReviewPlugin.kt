package com.ochipan.app_review

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Flutter Plugin for In-App Review.
 *
 * Implements [ReviewApi] using Google Play In-App Review API (review-ktx).
 * Automatically registers via Flutter's plugin system — no manual setUp required.
 */
class AppReviewPlugin : FlutterPlugin, ActivityAware, ReviewApi {

    private var activity: Activity? = null

    // region FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ReviewApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ReviewApi.setUp(binding.binaryMessenger, null)
    }

    // endregion

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // endregion

    // region ReviewApi

    override fun requestReview(callback: (Result<ReviewResult>) -> Unit) {
        val currentActivity = activity
        if (currentActivity == null) {
            callback(
                Result.success(
                    ReviewResult(
                        success = false,
                        errorMessage = "Activity is not available",
                    ),
                ),
            )
            return
        }

        val reviewManager = ReviewManagerFactory.create(currentActivity)
        val requestFlow = reviewManager.requestReviewFlow()

        requestFlow.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val reviewInfo = task.result
                val launchFlow = reviewManager.launchReviewFlow(currentActivity, reviewInfo)
                launchFlow.addOnCompleteListener {
                    callback(Result.success(ReviewResult(success = true)))
                }
            } else {
                callback(
                    Result.success(
                        ReviewResult(
                            success = false,
                            errorMessage = task.exception?.message
                                ?: "Failed to start review flow",
                        ),
                    ),
                )
            }
        }
    }

    override fun openStoreListing(appId: String?, callback: (Result<ReviewResult>) -> Unit) {
        val currentActivity = activity
        if (currentActivity == null) {
            callback(
                Result.success(
                    ReviewResult(
                        success = false,
                        errorMessage = "Activity is not available",
                    ),
                ),
            )
            return
        }

        val packageName = appId ?: currentActivity.packageName

        try {
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=$packageName"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            currentActivity.startActivity(intent)
            callback(Result.success(ReviewResult(success = true)))
        } catch (_: ActivityNotFoundException) {
            try {
                val intent = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse(
                        "https://play.google.com/store/apps/details?id=$packageName",
                    ),
                )
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                currentActivity.startActivity(intent)
                callback(Result.success(ReviewResult(success = true)))
            } catch (_: ActivityNotFoundException) {
                callback(
                    Result.success(
                        ReviewResult(
                            success = false,
                            errorMessage = "Could not open store listing",
                        ),
                    ),
                )
            }
        }
    }

    // endregion
}
