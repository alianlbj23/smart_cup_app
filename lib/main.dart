import 'package:flutter/material.dart';

import 'services/flutter_blue_plus_service.dart' show createBleService;
import 'state/cup_connection_manager.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 組裝點:BleService 實作由 createBleService() 提供,App 其餘部分只看到介面。
  final manager = CupConnectionManager(ble: createBleService())..init();
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
