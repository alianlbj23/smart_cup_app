import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'data/intake_repository.dart';
import 'services/flutter_blue_plus_service.dart' show createBleService;
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
  // 連線時由水位與姿態自動偵測喝水,寫入資料庫。要在 manager.init() 之前啟動,
  // 才接得到自動重連後的第一筆資料。
  IntakeRecorder(manager: manager, repo: repo).start();
  manager.init();
  // 桌面版關閉視窗前先斷開藍牙:Linux 的 BlueZ 不會因為 App 結束就斷線,
  // 連線留著的話水杯不會再廣播,下次開 App 會找不到水杯。最多等 3 秒。
  AppLifecycleListener(
    onExitRequested: () async {
      await manager
          .disconnect()
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      await db.close();
      return AppExitResponse.exit;
    },
  );
  runApp(SmartCupApp(manager: manager, repo: repo));
}

class SmartCupApp extends StatelessWidget {
  const SmartCupApp({super.key, required this.manager, required this.repo});

  final CupConnectionManager manager;
  final IntakeRepository repo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智慧水杯',
      theme: buildAppTheme(),
      home: AppShell(manager: manager, repo: repo),
    );
  }
}
