# app_review

ネイティブプラットフォーム API を使用した Flutter In-App Review プラグイン。

- **Android**: Google Play In-App Review API (`review-ktx`)
- **iOS**: StoreKit `SKStoreReviewController`

単純なレビューダイアログ表示だけでなく、**条件ベースのスマートトリガー**（初回起動からの経過日数・ユーザーアクション回数・リクエスト上限）を内蔵しています。

## 特徴

| 機能 | 説明 |
|---|---|
| ネイティブ API | Pigeon による型安全なプラットフォームチャネル（MethodChannel 不使用） |
| 自動登録 | Flutter プラグインシステムによる自動登録（MainActivity / AppDelegate への手動セットアップ不要） |
| `AppReviewClient` | ネイティブ API の薄い Dart ラッパー。`requestReview()` / `openStoreListing()` |
| `ReviewController` | 条件管理付きスマートコントローラー。SharedPreferences で状態を永続化 |
| `ReviewCondition` | 条件設定クラス。初回起動からの日数・アクション回数・リクエスト上限を設定可能 |
| アナリティクス連携 | `onReviewRequested` コールバックでレビューリクエスト結果をアプリ側に通知 |
| テスト可能 | コンストラクタ DI により `ReviewApi` / `AppReviewClient` をモック差し替え可能 |

## インストール

### `pubspec.yaml` に追加

```yaml
dependencies:
  app_review:
    path: app_review  # ローカルパッケージとして参照
```

または Git リポジトリから:

```yaml
dependencies:
  app_review:
    git:
      url: https://github.com/shimane0/app_review.git
```

### 要件

| プラットフォーム | 最低バージョン |
|---|---|
| Flutter | 3.28.0 以上 |
| Dart SDK | 3.9.0 以上 |
| Android | `minSdk 21`（`review-ktx` の要件） |
| iOS | iOS 14.0 以上（`SKStoreReviewController` の `requestReview(in:)` を使用） |

## 使い方

### 基本: レビューダイアログを直接表示

```dart
import 'package:app_review/app_review.dart';

final client = AppReviewClient();

// In-App Review ダイアログをリクエスト
final result = await client.requestReview();

if (!result.success) {
  // フォールバック: ストアページを開く
  await client.openStoreListing(
    iosAppId: '123456789',       // App Store の数値 ID
    androidPackageName: null,    // null でアプリのパッケージ名を自動検出
  );
}
```

### 推奨: 条件ベースのスマートトリガー

```dart
import 'package:app_review/app_review.dart';

final controller = ReviewController(
  condition: const ReviewCondition(
    minDaysFromFirstLaunch: 7,  // 初回起動から7日以上
    minActionCount: 3,          // ユーザーアクション3回以上
    maxRequestCount: 3,         // アプリ側リクエスト上限3回
  ),
  onReviewRequested: (result) {
    // アナリティクスにログ送信
    analytics.logReviewRequested(success: result.success);
  },
);

// アプリ初期化時に一度だけ呼ぶ（既に記録済みなら何もしない）
await controller.recordFirstLaunch();

// ユーザーが重要なアクション（シェア、保存、完了など）を実行した時に呼ぶ
await controller.recordAction();

// 全条件を満たせばレビューダイアログを表示
final didRequest = await controller.requestReviewIfEligible();
```

### Riverpod との統合例

```dart
@riverpod
ReviewController reviewController(Ref ref) {
  return ReviewController(
    onReviewRequested: (result) {
      appAnalytics.logReviewRequested(success: result.success);
    },
  );
}

@riverpod
class ReviewService extends _$ReviewService {
  @override
  void build() {}

  Future<void> recordFirstLaunchIfNeeded() async {
    await ref.read(reviewControllerProvider).recordFirstLaunch();
  }

  Future<void> recordShareAndRequestReview() async {
    final controller = ref.read(reviewControllerProvider);
    await controller.recordAction();
    await controller.requestReviewIfEligible();
  }
}
```

## API リファレンス

### `AppReviewClient`

ネイティブ In-App Review API の薄いラッパー。状態管理は行わない。

| メソッド | 説明 |
|---|---|
| `requestReview()` | ネイティブのレビューダイアログを表示（OS が実際に表示するかは制御不可） |
| `openStoreListing({iosAppId, androidPackageName})` | ストアページを直接開く（フォールバック用） |

### `ReviewController`

条件管理付きのスマートコントローラー。`SharedPreferences` で状態を永続化。

| メソッド | 説明 |
|---|---|
| `recordFirstLaunch()` | 初回起動日時を記録（記録済みなら何もしない） |
| `recordAction()` | ユーザーアクションカウントをインクリメント |
| `requestReviewIfEligible()` | 全条件を確認し、満たせばレビューをリクエスト。`true` = リクエスト実行済み |
| `reset()` | 全状態をリセット（テスト・デバッグ用） |

### `ReviewCondition`

| パラメータ | 型 | デフォルト | 説明 |
|---|---|---|---|
| `minDaysFromFirstLaunch` | `int` | `3` | レビュー可能になるまでの最低日数 |
| `minActionCount` | `int` | `1` | レビュー可能になるまでの最低アクション回数 |
| `maxRequestCount` | `int` | `3` | アプリ側のリクエスト上限回数 |

### `ReviewResult`

| フィールド | 型 | 説明 |
|---|---|---|
| `success` | `bool` | リクエストが正常に実行されたか |
| `errorMessage` | `String?` | 失敗時のエラーメッセージ |

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│  アプリ層                                        │
│  ReviewController (条件管理 + SharedPreferences)  │
│       ↓                                         │
│  AppReviewClient (薄いDartラッパー)               │
│       ↓                                         │
│  ReviewApi (Pigeon 生成インターフェース)            │
├─────────────────────────────────────────────────┤
│  ネイティブ層                                     │
│  Android: AppReviewPlugin (review-ktx)           │
│  iOS:     AppReviewPlugin (StoreKit)             │
└─────────────────────────────────────────────────┘
```

- **Pigeon** による型安全なコード生成（`@HostApi()`）
- Flutter プラグインシステムの自動登録（`onAttachedToEngine` / `register(with:)`）
- Android は `ActivityAware` を実装し、Activity ライフサイクルを安全に管理

## プラットフォーム固有の注意事項

### Android

- Google Play In-App Review API には表示回数の quota がある（アプリ側では判定不可）
- `launchReviewFlow` が完了しても、ユーザーが実際にレビューを書いたかは検知できない
- `openStoreListing` は `market://` intent を優先し、失敗時はブラウザにフォールバック

### iOS

- `SKStoreReviewController.requestReview(in:)` は 365日に最大3回まで OS が制御
- デバッグビルドでは常にダイアログが表示される（本番とは挙動が異なる）
- `openStoreListing` には App Store の数値 ID (`iosAppId`) が必要

## 開発

### Pigeon コード生成

ネイティブインターフェースを変更した場合:

```bash
cd app_review
dart run pigeon --input pigeons/messages.dart
```

### テスト

```dart
// AppReviewClient のモック差し替え
final mockApi = MockReviewApi();  // Pigeon の ReviewApi を実装
final client = AppReviewClient(api: mockApi);

// ReviewController のモック差し替え
final mockClient = MockAppReviewClient();
final controller = ReviewController(client: mockClient);
```

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照してください。
