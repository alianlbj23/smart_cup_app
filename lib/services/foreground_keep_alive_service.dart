// Android 前景服務(flutter_foreground_task):螢幕關掉、切到別的 App 時,
// 系統不會停掉 App,藍牙連線(在 App 主程式裡)才能一直維持。
// 只用來讓程序活著,不在服務裡跑任何工作(沒有 TaskHandler)。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'keep_alive_service.dart';

/// Android 用前景服務,其他平台不需要。
///
/// [isAppInForeground]:App 目前是否在畫面上;請求通知權限只能在前景做。
KeepAliveService createKeepAliveService({
  required bool Function() isAppInForeground,
}) =>
    Platform.isAndroid
        ? AndroidForegroundKeepAliveService(
            api: FlutterForegroundTaskApi(),
            hasBluetoothPermission: hasBluetoothConnectPermission,
            isAppInForeground: isAppInForeground,
          )
        : const NoopKeepAliveService();

/// 手機是否已經允許 App 連線藍牙裝置(Android 12 起的「鄰近裝置」權限)。
///
/// 只檢查,不會跳出詢問視窗(詢問由 flutter_blue_plus 在掃描、連線時處理)。
/// 查不到時回傳 null。原生端在 `MainActivity.kt`。
Future<bool?> hasBluetoothConnectPermission() async {
  try {
    return await _permissionChannel
        .invokeMethod<bool>('hasBluetoothConnect')
        .timeout(const Duration(seconds: 2));
  } on MissingPluginException catch (e) {
    debugPrint('[KeepAlive] 查不到藍牙權限(原生端沒有實作):$e');
  } on PlatformException catch (e) {
    debugPrint('[KeepAlive] 查不到藍牙權限:$e');
  } on TimeoutException catch (e) {
    debugPrint('[KeepAlive] 查藍牙權限逾時:$e');
  }
  return null;
}

const _permissionChannel = MethodChannel('smart_cup/permissions');

/// [AndroidForegroundKeepAliveService] 用到的 plugin 操作;包成介面是為了測試。
///
/// start / update / stop:成功回傳 null,失敗回傳錯誤。
abstract interface class ForegroundTaskApi {
  void init();
  Future<bool> hasNotificationPermission();

  /// 跳出系統的詢問視窗;回傳使用者是否允許。
  Future<bool> requestNotificationPermission();
  Future<bool> get isRunningService;
  Future<Object?> startService({required String title, required String text});
  Future<Object?> updateService({required String title, required String text});
  Future<Object?> stopService();
}

/// 真的 plugin(flutter_foreground_task)。
class FlutterForegroundTaskApi implements ForegroundTaskApi {
  static const _serviceId = 7101;

  @override
  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cup_connection',
        channelName: '水杯連線',
        channelDescription: '維持和水杯的藍牙連線(螢幕關掉也不會斷)',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // 背景重連的計時器要準時跑;不開的話 Android 省電模式會把它延後
        allowWakeLock: true,
        // 系統停掉 App 時藍牙程式也不在了,服務自己重啟沒有用,只會留下空通知
        allowAutoRestart: false,
        // 使用者把 App 從最近使用清單滑掉 = 要結束,服務跟著停
        stopWithTask: true,
      ),
    );
  }

  @override
  Future<bool> hasNotificationPermission() async =>
      await FlutterForegroundTask.checkNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<bool> requestNotificationPermission() async =>
      await FlutterForegroundTask.requestNotificationPermission() ==
      NotificationPermission.granted;

  @override
  Future<bool> get isRunningService => FlutterForegroundTask.isRunningService;

  @override
  Future<Object?> startService({
    required String title,
    required String text,
  }) async =>
      _error(await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: [ForegroundServiceTypes.connectedDevice],
        notificationTitle: title,
        notificationText: text,
      ));

  @override
  Future<Object?> updateService({
    required String title,
    required String text,
  }) async =>
      _error(await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      ));

  @override
  Future<Object?> stopService() async =>
      _error(await FlutterForegroundTask.stopService());

  static Object? _error(ServiceRequestResult result) =>
      result is ServiceRequestFailure ? result.error : null;
}

class AndroidForegroundKeepAliveService implements KeepAliveService {
  AndroidForegroundKeepAliveService({
    required this.api,
    required this.hasBluetoothPermission,
    required this.isAppInForeground,
  });

  final ForegroundTaskApi api;

  /// App 是否已經可以連線藍牙裝置;查不到回傳 null。
  final Future<bool?> Function() hasBluetoothPermission;

  /// App 目前是否在畫面上。
  final bool Function() isAppInForeground;

  bool _initialized = false;

  /// 這次執行已經跳過詢問視窗;使用者拒絕的話不再重複問。
  bool _askedNotificationPermission = false;

  void _init() {
    if (_initialized) return;
    api.init();
    _initialized = true;
  }

  @override
  Future<bool> start({required String title, required String text}) async {
    _init();
    // Android 14 起,connectedDevice 類型的前景服務要先有藍牙權限。沒有的話原生端
    // 會啟動失敗,而 plugin 要等 5 秒逾時才知道,所以先自己檢查。
    if (await _bluetoothPermissionDenied()) {
      debugPrint('[KeepAlive] 還沒有藍牙權限,先不啟動前景服務');
      return false;
    }
    // Android 13 起要通知權限才看得到常駐通知;沒給服務照樣能跑,只是通知不顯示
    await _requestNotificationPermissionIfNeeded();
    if (await api.isRunningService) {
      await update(title: title, text: text);
      return true;
    }
    final error = await api.startService(title: title, text: text);
    if (error != null) {
      debugPrint('[KeepAlive] 前景服務啟動失敗:$error');
      return false;
    }
    return true;
  }

  /// 確定沒有權限才回傳 true;查不到時當成有,照樣嘗試啟動。
  Future<bool> _bluetoothPermissionDenied() async {
    try {
      return await hasBluetoothPermission() == false;
    } catch (e, st) {
      debugPrint('[KeepAlive] 檢查藍牙權限失敗,照樣嘗試啟動:$e\n$st');
      return false;
    }
  }

  /// 詢問視窗只能在 App 在畫面上時跳出來;在背景就留到 [onAppForeground] 再問。
  /// 這次詢問後使用者允許了才回傳 true。
  Future<bool> _requestNotificationPermissionIfNeeded() async {
    if (_askedNotificationPermission || !isAppInForeground()) return false;
    if (await api.hasNotificationPermission()) return false;
    _askedNotificationPermission = true;
    return api.requestNotificationPermission();
  }

  @override
  Future<bool> onAppForeground() => _requestNotificationPermissionIfNeeded();

  @override
  Future<void> update({required String title, required String text}) async {
    final error = await api.updateService(title: title, text: text);
    if (error != null) throw StateError('更新前景服務通知失敗:$error');
  }

  @override
  Future<bool> stop() async {
    if (!await api.isRunningService) return true;
    final error = await api.stopService();
    if (error != null) {
      debugPrint('[KeepAlive] 前景服務停止失敗:$error');
      return false;
    }
    return true;
  }
}
