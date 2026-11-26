import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/services/update_installer.dart';
import 'package:stut_food_intake_project/services/update_service.dart';

TypeMatcher<UpdateException> _updateError(String code) =>
    isA<UpdateException>().having((e) => e.code, 'code', code);

final _sep = Platform.pathSeparator;

/// 桌面安裝器的測試會真的執行 tar 和背景的替換程式,只在 Linux / Windows 跑
/// (CI 的 Windows 建置工作也會跑這個檔案)。
final _desktopSkip = Platform.isLinux || Platform.isWindows
    ? null
    : '只在 Linux / Windows 執行';

final _platform =
    Platform.isWindows ? UpdatePlatform.windows : UpdatePlatform.linux;

/// 假的 App 執行檔:被啟動時在自己的資料夾寫下 `relaunched.txt`。
final _exeName = Platform.isWindows ? 'app.cmd' : 'app';

String _exeBody(String version) => Platform.isWindows
    ? '@echo off\r\nrem $version\r\necho $version> "%~dp0relaunched.txt"\r\n'
    : '#!/bin/sh\n# $version\necho $version > "\$(dirname "\$0")/relaunched.txt"\n';

void _writeExe(Directory dir, String version) {
  final f = File('${dir.path}$_sep$_exeName')
    ..writeAsStringSync(_exeBody(version));
  if (!Platform.isWindows) Process.runSync('chmod', ['+x', f.path]);
}

String _systemTar() => Platform.isWindows
    ? '${Platform.environment['SystemRoot']}\\System32\\tar.exe'
    : 'tar';

/// 把 [source] 的內容打包成 CI 發佈的格式(Linux:tar.gz;Windows:zip)。
File _pack(Directory source, Directory out) {
  final file = File('${out.path}$_sep${_platform.assetName}');
  final r = Process.runSync(_systemTar(), [
    if (Platform.isWindows) ...['-a', '-cf'] else '-czf',
    file.path,
    '-C',
    source.path,
    '.',
  ]);
  if (r.exitCode != 0) fail('打包失敗:${r.stderr}');
  return file;
}

/// 一個會自己結束的行程,當作「正在執行的 App」。
Future<Process> _fakeApp(int seconds) => Platform.isWindows
    ? Process.start('ping', ['-n', '${seconds + 1}', '127.0.0.1'])
    : Process.start('sleep', ['$seconds']);

Future<void> _waitFor(bool Function() done, {int seconds = 20}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('等了 $seconds 秒還沒完成');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  group('桌面版(解壓縮 → App 結束後替換檔案 → 重新啟動)', skip: _desktopSkip, () {
    late Directory root, installDir, workDir, source;
    late int exits;
    final running = <Process>[];

    DesktopUpdateInstaller installer(
      int pid, {
      Duration exitWait = const Duration(seconds: 30),
    }) =>
        DesktopUpdateInstaller(
          platform: _platform,
          installDir: installDir,
          executableName: _exeName,
          pid: pid,
          workDir: workDir,
          exitWait: exitWait,
          exitApp: () async => exits++,
        );

    String read(String relative) =>
        File('${installDir.path}$_sep$relative').readAsStringSync().trim();
    bool exists(String relative) =>
        File('${installDir.path}$_sep$relative').existsSync();

    setUp(() {
      exits = 0;
      root = Directory.systemTemp.createTempSync('update_installer_test_');
      installDir = Directory('${root.path}${_sep}install dir')..createSync();
      workDir = Directory('${root.path}${_sep}work');
      source = Directory('${root.path}${_sep}source')..createSync();
      // 目前安裝的 1.0.0。
      _writeExe(installDir, '1.0.0');
      Directory('${installDir.path}${_sep}data').createSync();
      File('${installDir.path}${_sep}data${_sep}asset.txt')
          .writeAsStringSync('old');
      // 新版 2.0.0 的內容。
      _writeExe(source, '2.0.0');
      Directory('${source.path}${_sep}data').createSync();
      File('${source.path}${_sep}data${_sep}asset.txt').writeAsStringSync('new');
      File('${source.path}${_sep}data${_sep}added.txt').writeAsStringSync('v2');
    });

    tearDown(() async {
      for (final p in running) {
        p.kill();
      }
      running.clear();
      // Windows 上背景程式剛結束時檔案可能還被占用,多試幾次。
      for (var i = 0;; i++) {
        try {
          root.deleteSync(recursive: true);
          break;
        } on FileSystemException {
          if (i >= 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });

    test('App 結束後換成新版的檔案,並重新啟動', () async {
      final app = await _fakeApp(2);
      running.add(app);

      await installer(app.pid).install(_pack(source, root));

      // install() 回來時已經要求 App 結束,檔案還是舊的(App 還在執行)。
      expect(exits, 1);
      expect(read('data${_sep}asset.txt'), 'old');
      expect(exists('relaunched.txt'), isFalse);

      await _waitFor(() => exists('relaunched.txt'));
      // 重新啟動的是新版的執行檔。
      await _waitFor(() => read('relaunched.txt') == '2.0.0');
      expect(read('data${_sep}asset.txt'), 'new');
      expect(read('data${_sep}added.txt'), 'v2');
      expect(File('${installDir.path}$_sep$_exeName').readAsStringSync(),
          _exeBody('2.0.0'));
    });

    test('App 一直沒有結束:不動安裝資料夾', () async {
      final app = await _fakeApp(30);
      running.add(app);

      await installer(app.pid, exitWait: const Duration(seconds: 1))
          .install(_pack(source, root));

      final log = File('${workDir.path}${_sep}update.log');
      await _waitFor(() => log.existsSync() && log.lengthSync() > 0);
      expect(read('data${_sep}asset.txt'), 'old');
      expect(exists('data${_sep}added.txt'), isFalse);
      expect(exists('relaunched.txt'), isFalse);
    });

    test('安裝檔不是壓縮檔:失敗,App 不會被關掉,安裝資料夾不變', () async {
      final bad = File('${root.path}$_sep${_platform.assetName}')
        ..writeAsStringSync('this is not an archive');

      await expectLater(
          installer(pid).install(bad), throwsA(_updateError(UpdateException.install)));

      expect(exits, 0);
      expect(read('data${_sep}asset.txt'), 'old');
    });

    test('壓縮檔裡沒有 App 的執行檔:失敗,App 不會被關掉', () async {
      File('${source.path}$_sep$_exeName').deleteSync();

      await expectLater(installer(pid).install(_pack(source, root)),
          throwsA(_updateError(UpdateException.install)));

      expect(exits, 0);
      expect(read('data${_sep}asset.txt'), 'old');
    });

    test('安裝檔不存在:失敗', () async {
      await expectLater(
          installer(pid).install(File('${root.path}${_sep}missing.zip')),
          throwsA(_updateError(UpdateException.install)));
      expect(exits, 0);
    });

    test('安裝資料夾不能寫入:失敗並請使用者手動下載,App 不會被關掉', skip: Platform.isWindows ? '用 chmod 模擬,只在 Linux 執行' : null, () async {
      Process.runSync('chmod', ['555', installDir.path]);
      addTearDown(() => Process.runSync('chmod', ['755', installDir.path]));

      await expectLater(
          installer(pid).install(_pack(source, root)),
          throwsA(_updateError(UpdateException.install)
              .having((e) => e.message, 'message', contains('手動'))));
      expect(exits, 0);
    });
  });

  group('Android(交給系統的安裝程式)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(AndroidUpdateInstaller.channelName);
    final calls = <MethodCall>[];

    void handle(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    setUp(calls.clear);
    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('把 APK 的路徑交給原生端', () async {
      handle((_) async => null);

      await const AndroidUpdateInstaller().install(File('/cache/updates/a.apk'));

      expect(calls.single.method, 'installApk');
      expect(calls.single.arguments, {'path': '/cache/updates/a.apk'});
    });

    test('還沒允許安裝應用程式:回報需要權限', () async {
      handle((_) async => throw PlatformException(code: 'NEEDS_PERMISSION'));

      await expectLater(
          const AndroidUpdateInstaller().install(File('/cache/updates/a.apk')),
          throwsA(_updateError(UpdateException.needsInstallPermission)));
    });

    test('原生端回報其他錯誤:安裝失敗', () async {
      handle((_) async =>
          throw PlatformException(code: 'INSTALL_FAILED', message: 'boom'));

      await expectLater(
          const AndroidUpdateInstaller().install(File('/cache/updates/a.apk')),
          throwsA(_updateError(UpdateException.install)));
    });

    test('原生端沒有實作(MissingPluginException):安裝失敗', () async {
      await expectLater(
          const AndroidUpdateInstaller().install(File('/cache/updates/a.apk')),
          throwsA(_updateError(UpdateException.install)));
    });
  });
}
