import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/services/update_service.dart';
import 'package:stut_food_intake_project/state/update_manager.dart';

import 'fakes/fake_update_server.dart';

void main() {
  late FakeUpdateServer server;
  late FakeUpdateInstaller installer;
  late Directory dir;

  UpdateManager manager({
    bool withInstaller = true,
    UpdatePlatform platform = UpdatePlatform.linux,
    Duration checkInterval = const Duration(hours: 6),
  }) {
    final m = UpdateManager(
      service: server.service(platform: platform),
      installer: withInstaller ? installer : null,
      downloadDir: () async => dir,
      checkInterval: checkInterval,
    );
    addTearDown(m.dispose);
    return m;
  }

  setUp(() {
    server = FakeUpdateServer();
    installer = FakeUpdateInstaller();
    dir = Directory.systemTemp.createTempSync('update_manager_test_');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('檢查更新', () {
    test('有新版:狀態變成 available,並通知畫面', () async {
      server.latest = '1.2.0';
      final m = manager();
      final phases = <UpdatePhase>[];
      m.addListener(() => phases.add(m.phase));

      await m.check();

      expect(phases, [UpdatePhase.checking, UpdatePhase.available]);
      expect(m.available!.version, '1.2.0');
      expect(m.currentVersion, '1.1.0');
      expect(m.canInstall, isTrue);
      expect(m.error, isNull);
    });

    test('已是最新版', () async {
      server.latest = '1.1.0';
      final m = manager();

      await m.check();

      expect(m.phase, UpdatePhase.upToDate);
      expect(m.available, isNull);
      expect(m.canInstall, isFalse);
    });

    test('檢查失敗:記下原因;先前查到的新版還在', () async {
      server.latest = '1.2.0';
      final m = manager();
      await m.check();

      server.checkStatus = 500;
      await m.check();

      expect(m.phase, UpdatePhase.failed);
      expect(m.error, contains('500'));
      expect(m.available!.version, '1.2.0');

      // 之後查詢成功就清掉錯誤。
      server.checkStatus = 200;
      await m.check();
      expect(m.phase, UpdatePhase.available);
      expect(m.error, isNull);
    });

    test('這個平台沒有安裝器(iOS / macOS):查得到新版,但不能自行安裝', () async {
      server.latest = '1.2.0';
      final m = manager(withInstaller: false, platform: UpdatePlatform.macos);

      await m.check();

      expect(m.available!.version, '1.2.0');
      expect(m.canInstall, isFalse);
    });

    test('新版沒有這個平台的安裝檔:不能自行安裝', () async {
      server
        ..latest = '1.2.0'
        ..assetNames = ['smart_cup_app-android.apk'];
      final m = manager();

      await m.check();

      expect(m.available!.version, '1.2.0');
      expect(m.canInstall, isFalse);
    });

    testWidgets('start():馬上檢查一次,之後每隔 checkInterval 再檢查', (tester) async {
      server.latest = '1.1.0';
      final m = manager(checkInterval: const Duration(hours: 6));

      m.start();
      await tester.pump();
      expect(server.checks, 1);
      expect(m.phase, UpdatePhase.upToDate);

      server.latest = '1.2.0';
      await tester.pump(const Duration(hours: 5, minutes: 59));
      expect(server.checks, 1);
      await tester.pump(const Duration(minutes: 2));
      expect(server.checks, 2);
      expect(m.available!.version, '1.2.0');

      m.dispose();
      await tester.pump(const Duration(hours: 12));
      expect(server.checks, 2);
    });
  });

  group('下載並安裝', () {
    test('下載到指定資料夾,交給安裝器;進度走到 100%', () async {
      server
        ..latest = '1.2.0'
        ..assetBytes = List.generate(3000, (i) => i % 251);
      final m = manager();
      await m.check();
      final seen = <(UpdatePhase, double?)>[];
      m.addListener(() => seen.add((m.phase, m.progress)));

      await m.install();

      final file = installer.installed.single;
      expect(file.parent.path, dir.path);
      expect(file.readAsBytesSync(), server.assetBytes);
      expect(seen.first, (UpdatePhase.downloading, 0.0));
      expect(seen, contains((UpdatePhase.downloading, 1.0)));
      expect(seen.map((s) => s.$1), contains(UpdatePhase.installing));
      // 安裝器回來後(Android:系統安裝畫面已跳出)回到可以再按一次的狀態。
      expect(m.phase, UpdatePhase.available);
      expect(m.progress, isNull);
      expect(m.error, isNull);
    });

    test('下載失敗:不呼叫安裝器,顯示原因,可以再試一次', () async {
      server.latest = '1.2.0';
      final m = manager();
      await m.check();

      server.downloadStatus = 503;
      await m.install();

      expect(installer.installed, isEmpty);
      expect(m.phase, UpdatePhase.failed);
      expect(m.error, contains('503'));
      expect(m.canInstall, isTrue);

      server.downloadStatus = 200;
      await m.install();
      expect(installer.installed, hasLength(1));
      expect(m.phase, UpdatePhase.available);
    });

    test('安裝器失敗(例如 Android 還沒允許安裝):顯示安裝器的訊息', () async {
      server.latest = '1.2.0';
      installer.error = const UpdateException(
          code: UpdateException.needsInstallPermission, message: '請允許安裝');
      final m = manager();
      await m.check();

      await m.install();

      expect(m.phase, UpdatePhase.failed);
      expect(m.error, '請允許安裝');
      expect(m.canInstall, isTrue);
    });

    test('沒有新版或不能自行安裝時,install() 什麼都不做', () async {
      server.latest = '1.1.0';
      final m = manager();
      await m.check();

      await m.install();

      expect(server.downloads, 0);
      expect(installer.installed, isEmpty);
      expect(m.phase, UpdatePhase.upToDate);
    });

    test('下載中再按一次不會重複下載', () async {
      server.latest = '1.2.0';
      final m = manager();
      await m.check();

      await Future.wait([m.install(), m.install()]);

      expect(server.downloads, 1);
      expect(installer.installed, hasLength(1));
    });
  });
}
