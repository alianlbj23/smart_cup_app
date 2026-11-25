import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'data/intake_repository.dart';
import 'services/care_api.dart';
import 'services/care_link_store.dart';
import 'services/flutter_blue_plus_service.dart' show createBleService;
import 'state/care_link_manager.dart';
import 'state/care_sync.dart';
import 'state/cup_connection_manager.dart';
import 'state/intake_recorder.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 組裝點:BleService 實作由 createBleService() 提供,App 其餘部分只看到介面。
  final manager = CupConnectionManager(ble: createBleService());
  // 飲水紀錄存在本機 SQLite(手機/桌面為 App 資料夾內的 smart_cup.sqlite)。
  final db = AppDatabase();
  final repo = IntakeRepository(db);
  await repo.init();
  // 照護系統:讀取儲存的連結(伺服器位址、token、住民、目標)。這一步不連網;
  // 讀取失敗時記 log、當成尚未連結繼續啟動(儲存的資料不會被動到)。
  final careStore = CareLinkStore();
  final careApi = CareApi();
  final care = CareLinkManager(
      api: careApi, store: careStore, repo: repo, cups: manager);
  try {
    await care.load();
  } catch (e, st) {
    debugPrint('[main] 讀取照護系統連結失敗:$e\n$st');
  }
  // 已連結時在背景上傳紀錄、回報狀態、更新每日目標;尚未連結時不連網。
  final careSync = CareSync(
      api: careApi, link: care, repo: repo, cups: manager, store: careStore);
  // 連線時記錄喝水/加水:韌體 ≥ 0.3.0 由韌體送事件(0x07),舊韌體由 App 從水位與
  // 姿態偵測。要在 manager.init() 之前啟動,才接得到自動重連後的第一筆資料。
  IntakeRecorder(manager: manager, repo: repo).start();
  manager.init();
  unawaited(careSync.start().catchError((Object e, StackTrace st) {
    debugPrint('[main] 照護系統同步無法啟動:$e\n$st');
  }));
  // 桌面版關閉視窗前先斷開藍牙:Linux 的 BlueZ 不會因為 App 結束就斷線,
  // 連線留著的話水杯不會再廣播,下次開 App 會找不到水杯。最多等 3 秒。
  AppLifecycleListener(
    onExitRequested: () async {
      careSync.dispose();
      care.dispose();
      careApi.close();
      await manager
          .disconnect()
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      await db.close();
      return AppExitResponse.exit;
    },
  );
  runApp(SmartCupApp(
      manager: manager, repo: repo, care: care, careSync: careSync));
}

class SmartCupApp extends StatelessWidget {
  const SmartCupApp({
    super.key,
    required this.manager,
    required this.repo,
    this.care,
    this.careSync,
  });

  final CupConnectionManager manager;
  final IntakeRepository repo;
  final CareLinkManager? care;
  final CareSync? careSync;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智慧水杯',
      theme: buildAppTheme(),
      home: AppShell(
          manager: manager, repo: repo, care: care, careSync: careSync),
    );
  }
}
