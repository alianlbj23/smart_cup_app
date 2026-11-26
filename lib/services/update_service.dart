/// App 自動更新的網路層:向 GitHub Releases 查詢最新版本、下載安裝檔。
///
/// 來源是 [updateRepo] 的 `releases/latest`(CI 在 `pubspec.yaml` 的版本號變大時
/// 自動發佈,見 `.github/workflows/build-release.yml`)。規則和 `care_api.dart` 一樣:
/// - 所有請求都有 timeout;下載另外有「多久沒收到資料」的 timeout。
/// - GitHub 回傳的每個欄位都先驗證型別與範圍;安裝檔的下載網址必須是這個 repo
///   該版本 release 底下的固定檔名,不合就當成 `BAD_RESPONSE`。
/// - 任何失敗都丟出 [UpdateException](不吞例外)並記 log。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../app_info.dart';

/// `major.minor.patch` 版本號;可以有 `v` 開頭(release 的 tag 是 `v1.2.0`)。
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');

  /// 格式不對(少一段、有 `-beta` 之類的後綴…)時回傳 null。
  static AppVersion? tryParse(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// 有發佈安裝檔的平台,以及 release 裡對應的檔名(CI 打包時用同樣的名字)。
enum UpdatePlatform {
  android('smart_cup_app-android.apk'),
  ios('smart_cup_app-ios-unsigned.ipa'),
  linux('smart_cup_app-linux-x64.tar.gz'),
  windows('smart_cup_app-windows-x64.zip'),
  macos('smart_cup_app-macos.zip');

  const UpdatePlatform(this.assetName);

  final String assetName;

  /// App 能不能自己下載並安裝新版。iOS 不允許 App 在商店以外自行更新;macOS 版在
  /// App Sandbox 裡,不能替換自己。這兩個平台只提示有新版並提供下載頁的連結。
  bool get canSelfInstall =>
      this == android || this == linux || this == windows;

  /// 目前執行的平台;Web 沒有安裝檔,回傳 null(不檢查更新)。
  static UpdatePlatform? current() {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      TargetPlatform.linux => linux,
      TargetPlatform.windows => windows,
      TargetPlatform.macOS => macos,
      TargetPlatform.fuchsia => null,
    };
  }
}

/// release 裡的一個安裝檔。
@immutable
class UpdateAsset {
  const UpdateAsset({required this.name, required this.size, required this.url});

  final String name;

  /// 位元組數(GitHub 記載的大小,下載完會核對)。
  final int size;
  final Uri url;
}

/// 比目前新的版本。
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    required this.asset,
  });

  /// 新版的版本號,例如 `1.2.0`。
  final String version;

  /// release 的說明;沒有時為空字串。
  final String notes;

  /// release 的網頁(手動下載用)。
  final Uri pageUrl;

  /// 這個平台的安裝檔;這一版沒有發佈這個平台時為 null。
  final UpdateAsset? asset;
}

/// 檢查更新、下載、安裝的所有失敗。
class UpdateException implements Exception {
  const UpdateException({required this.code, required this.message});

  final String code;

  /// 中文訊息,可以直接顯示。
  final String message;

  static const network = 'NETWORK';
  static const timeout = 'TIMEOUT';
  static const http = 'HTTP';
  static const badResponse = 'BAD_RESPONSE';

  /// 下載到的內容和 release 記載的大小不符。
  static const badDownload = 'BAD_DOWNLOAD';

  /// 寫不進磁碟(空間不足、沒有權限…)。
  static const storage = 'STORAGE';

  /// 安裝步驟失敗(見 `update_installer.dart`)。
  static const install = 'INSTALL';

  /// Android 還沒允許這個 App 安裝應用程式;已經帶使用者到系統設定。
  static const needsInstallPermission = 'NEEDS_INSTALL_PERMISSION';

  @override
  String toString() => 'UpdateException($code): $message';
}

/// 向 GitHub Releases 查詢與下載。[http.Client] 可以注入(測試用 `MockClient`)。
class UpdateService {
  UpdateService({
    http.Client? client,
    this.repo = updateRepo,
    String currentVersion = appVersion,
    required this.platform,
    this.timeout = const Duration(seconds: 20),
    this.downloadIdleTimeout = const Duration(seconds: 30),
  })  : _client = client ?? _defaultClient(),
        current = AppVersion.tryParse(currentVersion) ??
            (throw ArgumentError.value(
                currentVersion, 'currentVersion', '不是 major.minor.patch')) {
    if (!_repoPattern.hasMatch(repo)) {
      throw ArgumentError.value(repo, 'repo', '要是 owner/name');
    }
  }

  /// 建立連線的時間上限。
  static const connectTimeout = Duration(seconds: 10);

  /// 安裝檔的大小上限;超過就當成回應有問題。
  static const maxAssetBytes = 500 * 1024 * 1024;

  static final _repoPattern = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');

  final http.Client _client;

  /// GitHub repo,`owner/name`。
  final String repo;

  /// 目前安裝的版本。
  final AppVersion current;
  final UpdatePlatform platform;

  /// 查詢最新版本、以及下載開始收到回應的時間上限。
  final Duration timeout;

  /// 下載途中多久沒收到資料就放棄。
  final Duration downloadIdleTimeout;

  static http.Client _defaultClient() =>
      IOClient(HttpClient()..connectionTimeout = connectTimeout);

  void close() => _client.close();

  UpdateException _log(String what, UpdateException e) {
    debugPrint('[Update] $what 失敗:$e');
    return e;
  }

  /// 查詢最新的 release。比目前的版本新就回傳 [UpdateInfo];已經是最新、或還沒有
  /// 任何 release 時回傳 null。
  Future<UpdateInfo?> check() async {
    const what = '檢查更新';
    final url = Uri.https('api.github.com', '/repos/$repo/releases/latest');
    // 逾時的時候用 abortTrigger 真的中止連線,不讓它在背景繼續跑。
    final abort = Completer<void>();
    final request = http.AbortableRequest('GET', url,
        abortTrigger: abort.future)
      ..headers['Accept'] = 'application/vnd.github+json'
      ..headers['X-GitHub-Api-Version'] = '2022-11-28';

    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      abort.complete();
      throw _log(
        what,
        UpdateException(
          code: UpdateException.timeout,
          message: '檢查更新逾時(${timeout.inSeconds} 秒內沒有回應)',
        ),
      );
    } catch (e) {
      throw _log(
        what,
        UpdateException(
          code: UpdateException.network,
          message: '無法連上更新伺服器(${e.runtimeType})',
        ),
      );
    }

    final status = response.statusCode;
    // 還沒有發佈過任何 release。
    if (status == 404) return null;
    if (status != 200) {
      throw _log(
        what,
        UpdateException(
          code: UpdateException.http,
          message: status == 403 || status == 429
              ? '更新伺服器暫時拒絕查詢(HTTP $status),請稍後再試'
              : '更新伺服器回應錯誤(HTTP $status)',
        ),
      );
    }
    try {
      return _parseRelease(
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)));
    } on FormatException catch (e) {
      throw _log(
        what,
        UpdateException(
          code: UpdateException.badResponse,
          message: '更新伺服器回應的格式不符(${e.message})',
        ),
      );
    }
  }

  /// 驗證並轉換 `releases/latest` 的回應;格式不符時丟出 [FormatException]。
  UpdateInfo? _parseRelease(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('release 不是物件');
    }
    final tag = json['tag_name'];
    if (tag is! String) throw const FormatException('tag_name 不是字串');
    final version = AppVersion.tryParse(tag);
    if (version == null) throw const FormatException('tag_name 不是版本號');
    if (json['draft'] == true || json['prerelease'] == true) return null;
    if (version.compareTo(current) <= 0) return null;

    final page = json['html_url'];
    final pageUrl = page is String ? Uri.tryParse(page) : null;
    if (pageUrl == null ||
        pageUrl.scheme != 'https' ||
        pageUrl.host != 'github.com' ||
        !pageUrl.path.startsWith('/$repo/releases/')) {
      throw const FormatException('html_url 不是這個 repo 的 release');
    }
    final assets = json['assets'];
    if (assets is! List) throw const FormatException('assets 不是陣列');
    final body = json['body'];

    UpdateAsset? asset;
    for (final a in assets) {
      if (a is! Map || a['name'] != platform.assetName) continue;
      final size = a['size'], url = a['browser_download_url'];
      if (size is! int || size <= 0 || size > maxAssetBytes) {
        throw const FormatException('安裝檔的大小不合理');
      }
      // 只接受這個 repo、這個版本底下的固定檔名,避免被導去別的地方下載。
      final expected =
          'https://github.com/$repo/releases/download/$tag/${platform.assetName}';
      if (url != expected) {
        throw const FormatException('安裝檔的下載網址不符');
      }
      asset = UpdateAsset(
          name: platform.assetName, size: size, url: Uri.parse(expected));
      break;
    }
    return UpdateInfo(
      version: version.toString(),
      notes: body is String ? body.trim() : '',
      pageUrl: pageUrl,
      asset: asset,
    );
  }

  /// 把 [asset] 下載到 [dir],檔名是 [UpdateAsset.name](已存在就覆蓋)。
  ///
  /// 下載完會核對大小;任何失敗都丟出 [UpdateException],而且不留下不完整的檔案。
  Future<File> download(
    UpdateAsset asset,
    Directory dir, {
    void Function(int received, int total)? onProgress,
  }) async {
    const what = '下載安裝檔';
    final target = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    final part = File('${target.path}.part');
    IOSink? sink;
    try {
      await dir.create(recursive: true);
      final response =
          await _client.send(http.Request('GET', asset.url)).timeout(timeout);
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw UpdateException(
          code: UpdateException.http,
          message: '下載失敗(HTTP ${response.statusCode})',
        );
      }
      sink = part.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(downloadIdleTimeout)) {
        received += chunk.length;
        if (received > asset.size) break;
        sink.add(chunk);
        onProgress?.call(received, asset.size);
      }
      await sink.close();
      sink = null;
      if (received != asset.size) {
        throw UpdateException(
          code: UpdateException.badDownload,
          message: '下載的檔案大小不符(預期 ${asset.size},實際'
              '${received > asset.size ? '超過' : ' $received'}),請再試一次',
        );
      }
      if (await target.exists()) await target.delete();
      return await part.rename(target.path);
    } on UpdateException catch (e) {
      throw _log(what, e);
    } on TimeoutException {
      throw _log(
        what,
        const UpdateException(
            code: UpdateException.timeout, message: '下載逾時,請確認網路後再試一次'),
      );
    } on FileSystemException catch (e) {
      throw _log(
        what,
        UpdateException(
          code: UpdateException.storage,
          message: '無法儲存下載的檔案(${e.osError?.message ?? e.message})',
        ),
      );
    } catch (e) {
      throw _log(
        what,
        UpdateException(
          code: UpdateException.network,
          message: '下載中斷(${e.runtimeType}),請確認網路後再試一次',
        ),
      );
    } finally {
      // 失敗時 sink 還開著:關掉並刪除不完整的檔案。清理失敗只記 log,
      // 不蓋掉原本的錯誤。
      try {
        await sink?.close();
        if (await part.exists()) await part.delete();
      } on FileSystemException catch (e) {
        debugPrint('[Update] 清除不完整的下載檔失敗:$e');
      }
    }
  }
}
