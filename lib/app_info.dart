/// App 版本(不含 build number),送給照護系統的 `app_version`。
///
/// 要和 `pubspec.yaml` 的 `version` 一致(`test/app_info_test.dart` 會檢查);
/// 這個專案沒有 package_info_plus,所以寫成常數。
const appVersion = '1.1.4';

/// 自動更新的來源:這個 GitHub repo(`owner/name`)的 Releases。repo 必須是公開的,
/// App 才能不帶 token 查詢與下載。
const updateRepo = 'alianlbj23/smart_cup_app';
