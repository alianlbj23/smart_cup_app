import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/update_installer.dart';
import '../services/update_service.dart';

/// 自動更新目前在做什麼。
enum UpdatePhase {
  /// 還沒檢查過。
  idle,
  checking,

  /// 檢查過了,沒有比較新的版本。
  upToDate,

  /// 有新版([UpdateManager.available]),等使用者按更新。
  available,
  downloading,

  /// 下載完,正在交給安裝器。
  installing,

  /// 最近一次檢查或更新失敗([UpdateManager.error])。
  failed,
}

/// App 自動更新的狀態:定期檢查有沒有新版,使用者按下更新時下載並安裝。
///
/// 所有方法都不會丟出例外:失敗時 [phase] 變成 [UpdatePhase.failed]、原因放在
/// [error](訊息可以直接顯示),細節由 `update_service.dart` / `update_installer.dart`
/// 記 log。
class UpdateManager extends ChangeNotifier {
  UpdateManager({
    required this._service,
    required this._installer,
    required this._downloadDir,
    this.checkInterval = const Duration(hours: 6),
  });

  final UpdateService _service;

  /// 這個平台的安裝器;不能自行更新的平台(iOS / macOS)為 null。
  final UpdateInstaller? _installer;
  final Future<Directory> Function() _downloadDir;

  /// [start] 之後每隔多久檢查一次(App 可能好幾天不關)。
  final Duration checkInterval;

  Timer? _timer;
  bool _disposed = false;
  UpdatePhase _phase = UpdatePhase.idle;
  UpdateInfo? _available;
  String? _error;
  double? _progress;

  UpdatePhase get phase => _phase;

  /// 比目前新的版本;沒有或還沒查到時為 null。
  UpdateInfo? get available => _available;

  /// 最近一次失敗的原因;成功後清掉。
  String? get error => _error;

  /// 下載進度 0–1;不在下載時為 null。
  double? get progress => _progress;

  String get currentVersion => _service.current.toString();
  UpdatePlatform get platform => _service.platform;

  bool get busy =>
      _phase == UpdatePhase.checking ||
      _phase == UpdatePhase.downloading ||
      _phase == UpdatePhase.installing;

  /// 能不能按「下載並安裝」:有新版、這個平台能自行安裝、新版有這個平台的安裝檔。
  bool get canInstall => _installer != null && _available?.asset != null;

  /// 馬上檢查一次,之後每隔 [checkInterval] 再檢查。App 啟動時呼叫一次。
  void start() {
    if (_timer != null || _disposed) return;
    _timer = Timer.periodic(checkInterval, (_) => unawaited(check()));
    unawaited(check());
  }

  void _set(UpdatePhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  /// 檢查有沒有新版。正在檢查或更新時不重複做。
  Future<void> check() async {
    if (busy || _disposed) return;
    _set(UpdatePhase.checking);
    try {
      final info = await _service.check();
      _available = info;
      _error = null;
      _set(info == null ? UpdatePhase.upToDate : UpdatePhase.available);
    } on UpdateException catch (e) {
      // 先前查到的新版留著:只是這次連不上,不代表新版不見了。
      _error = e.message;
      _set(UpdatePhase.failed);
    }
  }

  /// 下載新版並交給安裝器。[canInstall] 為 false、或正在忙的時候什麼都不做。
  Future<void> install() async {
    final asset = _available?.asset, installer = _installer;
    if (busy || _disposed || asset == null || installer == null) return;
    _error = null;
    _progress = 0;
    _set(UpdatePhase.downloading);
    try {
      final file = await _service.download(
        asset,
        await _downloadDir(),
        onProgress: (received, total) {
          final p = received / total;
          // 每 1% 才通知一次,不要每個封包都重畫。
          if (p >= 1 || p - (_progress ?? 0) >= 0.01) {
            _progress = p;
            _set(UpdatePhase.downloading);
          }
        },
      );
      _progress = null;
      _set(UpdatePhase.installing);
      await installer.install(file);
      // Android:系統的安裝畫面已經跳出,使用者按取消的話可以再按一次。
      // 桌面:App 即將結束。
      _set(UpdatePhase.available);
    } on UpdateException catch (e) {
      _fail(e.message);
    } catch (e, st) {
      debugPrint('[Update] 更新失敗:$e\n$st');
      _fail('更新失敗(${e.runtimeType})');
    }
  }

  void _fail(String message) {
    _error = message;
    _progress = null;
    _set(UpdatePhase.failed);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _service.close();
    super.dispose();
  }
}

/// 組裝這個平台的 [UpdateManager];沒有安裝檔的平台(Web)回傳 null。
///
/// [exitApp] 要讓 App 正常結束(桌面版換檔案前用)。
Future<UpdateManager?> createUpdateManager({
  required Future<void> Function() exitApp,
}) async {
  final platform = UpdatePlatform.current();
  if (platform == null) return null;
  // Android 的安裝程式只讀得到快取資料夾底下的這個子資料夾。
  final dir = Directory(
      '${(await getApplicationCacheDirectory()).path}${Platform.pathSeparator}'
      '${AndroidUpdateInstaller.downloadDirName}');
  return UpdateManager(
    service: UpdateService(platform: platform),
    installer: createUpdateInstaller(platform, workDir: dir, exitApp: exitApp),
    downloadDir: () async => dir,
  );
}
