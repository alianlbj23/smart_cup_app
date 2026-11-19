import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'services/flutter_blue_plus_service.dart' show createBleService;
import 'state/cup_connection_manager.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 組裝點:BleService 實作由 createBleService() 提供,App 其餘部分只看到介面。
  final manager = CupConnectionManager(ble: createBleService())..init();
  // 桌面版關閉視窗前先斷開藍牙:Linux 的 BlueZ 不會因為 App 結束就斷線,
  // 連線留著的話水杯不會再廣播,下次開 App 會找不到水杯。最多等 3 秒。
  AppLifecycleListener(
    onExitRequested: () async {
      await manager
          .disconnect()
          .timeout(const Duration(seconds: 3), onTimeout: () {});
      return AppExitResponse.exit;
    },
  );
  runApp(SmartCupApp(manager: manager));
}

class SmartCupApp extends StatelessWidget {
  const SmartCupApp({super.key, required this.manager});

  final CupConnectionManager manager;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智慧水杯',
      theme: buildAppTheme(),
      home: AppShell(manager: manager),
    );
  }
}
