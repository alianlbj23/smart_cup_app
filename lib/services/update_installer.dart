/// App 自動更新的安裝步驟:把 `update_service.dart` 下載好的安裝檔裝起來。
///
/// - Android:交給系統的安裝程式([AndroidUpdateInstaller]);系統一定會先問使用者。
/// - Linux / Windows:先解壓縮到暫存資料夾,再啟動一個背景程式,等 App 結束後把
///   新檔案蓋進安裝資料夾並重新啟動([DesktopUpdateInstaller])。
/// - iOS / macOS:App 不能自行更新,沒有安裝器(見 [UpdatePlatform.canSelfInstall])。
///
/// 任何失敗都丟出 [UpdateException] 並記 log。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'update_service.dart';

/// 安裝下載好的安裝檔。
abstract interface class UpdateInstaller {
  /// 成功回來時,系統的安裝畫面已經跳出(Android),或 App 即將結束並由背景程式
  /// 換成新版後重新啟動(桌面)。
  Future<void> install(File package);
}

/// 這個平台的安裝器;不能自行更新的平台回傳 null。
///
/// [workDir] 是放解壓縮內容與 log 的暫存資料夾;[exitApp] 要讓 App 正常結束
/// (桌面版用,結束前要先斷開藍牙,所以由組裝點提供)。
UpdateInstaller? createUpdateInstaller(
  UpdatePlatform platform, {
  required Directory workDir,
  required Future<void> Function() exitApp,
}) {
  switch (platform) {
    case UpdatePlatform.android:
      return const AndroidUpdateInstaller();
    case UpdatePlatform.linux || UpdatePlatform.windows:
      final exe = File(Platform.resolvedExecutable);
      return DesktopUpdateInstaller(
        platform: platform,
        installDir: exe.parent,
        executableName: exe.uri.pathSegments.last,
        pid: pid,
        workDir: workDir,
        exitApp: exitApp,
      );
    case UpdatePlatform.ios || UpdatePlatform.macos:
      return null;
  }
}

/// Android:透過 `MainActivity` 的 MethodChannel 開啟系統的安裝程式。
class AndroidUpdateInstaller implements UpdateInstaller {
  const AndroidUpdateInstaller();

  /// 和 `android/.../MainActivity.kt` 的頻道名稱一致。
  static const channelName = 'smart_cup/update';

  /// APK 必須下載到暫存資料夾底下的這個子資料夾:`MainActivity` 只接受這裡的檔案,
  /// `res/xml/update_file_paths.xml` 也只開放這個資料夾給安裝程式讀取。
  static const downloadDirName = 'smart_cup_update';

  static const _channel = MethodChannel(channelName);

  @override
  Future<void> install(File package) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': package.path});
    } on PlatformException catch (e) {
      debugPrint('[Update] 開啟安裝程式失敗:${e.code} ${e.message}');
      if (e.code == 'NEEDS_PERMISSION') {
        throw const UpdateException(
          code: UpdateException.needsInstallPermission,
          message: '請在剛開啟的系統設定裡允許「智慧水杯」安裝應用程式,再回來按一次更新',
        );
      }
      throw UpdateException(
        code: UpdateException.install,
        message: '無法開啟安裝程式(${e.code})',
      );
    } on MissingPluginException catch (e) {
      debugPrint('[Update] 開啟安裝程式失敗:$e');
      throw const UpdateException(
        code: UpdateException.install,
        message: '這個版本不支援自動安裝,請到下載頁手動下載新版',
      );
    }
  }
}

/// Linux / Windows:解壓縮 → 等 App 結束 → 覆蓋安裝資料夾 → 重新啟動。
///
/// 解壓縮在 App 還開著的時候做,壓縮檔有問題就直接失敗,不會動到安裝資料夾。
/// 覆蓋檔案由背景程式(Linux:`/bin/sh`;Windows:PowerShell)在 App 結束後進行;
/// App 在 [exitWait] 內沒有結束的話,背景程式什麼都不做,只在 `update.log` 留紀錄。
class DesktopUpdateInstaller implements UpdateInstaller {
  DesktopUpdateInstaller({
    required this.platform,
    required this.installDir,
    required this.executableName,
    required this.pid,
    required this.workDir,
    required this.exitApp,
    this.exitWait = const Duration(seconds: 60),
    this.extractTimeout = const Duration(minutes: 2),
  }) : assert(platform == UpdatePlatform.linux ||
            platform == UpdatePlatform.windows);

  final UpdatePlatform platform;

  /// App 的安裝資料夾(執行檔所在的資料夾)。
  final Directory installDir;

  /// 執行檔的檔名(在 [installDir] 底下)。
  final String executableName;

  /// 目前這個 App 的行程 ID;背景程式等它結束才覆蓋檔案。
  final int pid;
  final Directory workDir;

  /// 讓 App 正常結束。
  final Future<void> Function() exitApp;

  /// 背景程式最多等 App 多久。
  final Duration exitWait;
  final Duration extractTimeout;

  bool get _windows => platform == UpdatePlatform.windows;
  String get _sep => Platform.pathSeparator;

  UpdateException _fail(String message) {
    debugPrint('[Update] 安裝失敗:$message');
    return UpdateException(code: UpdateException.install, message: message);
  }

  @override
  Future<void> install(File package) async {
    if (!await package.exists()) throw _fail('找不到下載的安裝檔');
    await _checkWritable();

    final staging = Directory('${workDir.path}${_sep}staging');
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
    } on FileSystemException catch (e) {
      throw _fail('無法建立暫存資料夾(${e.osError?.message ?? e.message})');
    }
    await _extract(package, staging);
    if (!await File('${staging.path}$_sep$executableName').exists()) {
      throw _fail('安裝檔的內容不正確(找不到 $executableName)');
    }

    final log = File('${workDir.path}${_sep}update.log');
    try {
      if (_windows) {
        await _startWindowsHelper(staging, log);
      } else {
        await _startLinuxHelper(staging, log);
      }
    } on ProcessException catch (e) {
      throw _fail('無法啟動更新程式(${e.message})');
    }
    debugPrint('[Update] 已啟動更新程式,App 即將結束並重新啟動');
    await exitApp();
  }

  /// 安裝資料夾不能寫入(例如放在 Program Files 或 /opt)時,先擋下來。
  Future<void> _checkWritable() async {
    final probe = File('${installDir.path}$_sep.update_probe_$pid');
    try {
      await probe.writeAsBytes(const [], flush: true);
      await probe.delete();
    } on FileSystemException {
      throw _fail('App 所在的資料夾無法寫入(${installDir.path}),請到下載頁手動下載新版');
    }
  }

  String get _systemRoot =>
      Platform.environment['SystemRoot'] ?? r'C:\Windows';

  /// 用系統的 tar 解壓縮(Windows 10 起內建的 `tar.exe` 可以解 zip)。
  Future<void> _extract(File package, Directory staging) async {
    final tar = _windows ? '$_systemRoot\\System32\\tar.exe' : 'tar';
    final Process process;
    try {
      process = await Process.start(
          tar, ['-xf', package.path, '-C', staging.path]);
    } on ProcessException catch (e) {
      throw _fail('無法執行解壓縮程式(${e.message})');
    }
    unawaited(process.stdout.drain<void>());
    final stderrText = process.stderr
        .transform(const SystemEncoding().decoder)
        .join()
        .catchError((Object e) => '(讀不到錯誤訊息:$e)');
    final code = await process.exitCode.timeout(extractTimeout, onTimeout: () {
      process.kill();
      return -1;
    });
    if (code != 0) {
      debugPrint('[Update] 解壓縮失敗(exit $code):${await stderrText}');
      throw _fail(code == -1 ? '解壓縮逾時' : '安裝檔無法解壓縮,請再試一次');
    }
  }

  // 參數:$1 pid、$2 解壓縮好的資料夾、$3 安裝資料夾、$4 執行檔、$5 log、
  // $6 每 0.2 秒檢查一次,最多檢查幾次。
  static const _linuxScript = r'''
pid="$1"; staging="$2"; dest="$3"; exe="$4"; log="$5"; tries="$6"
exec >>"$log" 2>&1
i=0
while kill -0 "$pid" 2>/dev/null; do
  i=$((i+1))
  if [ "$i" -gt "$tries" ]; then
    echo "$(date) app (pid $pid) is still running; update aborted"
    exit 1
  fi
  sleep 0.2
done
if ! cp -a "$staging/." "$dest/"; then
  echo "$(date) copying the new version failed"
  exit 1
fi
rm -rf "$staging"
echo "$(date) updated; starting $exe"
cd "$dest" || exit 1
exec "./$exe"
''';

  Future<void> _startLinuxHelper(Directory staging, File log) async {
    await Process.start(
      '/bin/sh',
      [
        '-c',
        _linuxScript,
        'smart_cup_update',
        '$pid',
        staging.path,
        installDir.path,
        executableName,
        log.path,
        '${(exitWait.inMilliseconds / 200).ceil()}',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  // 路徑等參數都從環境變數讀,不拼進指令字串;整段只用單引號。
  // 剛結束的 App 可能還占用 DLL,複製失敗時最多重試 5 次。
  static const _windowsScript = r"$ErrorActionPreference = 'Stop'; "
      r"try { "
      r"$p = Get-Process -Id ([int]$env:SMART_CUP_UPDATE_PID) -ErrorAction SilentlyContinue; "
      r"if ($p -and -not $p.WaitForExit([int]$env:SMART_CUP_UPDATE_WAIT_MS)) { throw 'app is still running; update aborted' }; "
      r"$n = 0; "
      r"while ($true) { "
      r"try { Get-ChildItem -LiteralPath $env:SMART_CUP_UPDATE_STAGING -Force | Copy-Item -Destination $env:SMART_CUP_UPDATE_DEST -Recurse -Force; break } "
      r"catch { $n++; if ($n -ge 5) { throw }; Start-Sleep -Seconds 1 } "
      r"}; "
      r"Remove-Item -LiteralPath $env:SMART_CUP_UPDATE_STAGING -Recurse -Force; "
      r"Add-Content -LiteralPath $env:SMART_CUP_UPDATE_LOG -Value ((Get-Date -Format o) + ' updated'); "
      r"Start-Process -FilePath (Join-Path $env:SMART_CUP_UPDATE_DEST $env:SMART_CUP_UPDATE_EXE) -WorkingDirectory $env:SMART_CUP_UPDATE_DEST "
      r"} catch { "
      r"Add-Content -LiteralPath $env:SMART_CUP_UPDATE_LOG -Value ((Get-Date -Format o) + ' ' + $_); "
      r"exit 1 }";

  Future<void> _startWindowsHelper(Directory staging, File log) async {
    await Process.start(
      '$_systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        _windowsScript,
      ],
      environment: {
        'SMART_CUP_UPDATE_PID': '$pid',
        'SMART_CUP_UPDATE_WAIT_MS': '${exitWait.inMilliseconds}',
        'SMART_CUP_UPDATE_STAGING': staging.path,
        'SMART_CUP_UPDATE_DEST': installDir.path,
        'SMART_CUP_UPDATE_EXE': executableName,
        'SMART_CUP_UPDATE_LOG': log.path,
      },
      mode: ProcessStartMode.detached,
    );
  }
}
