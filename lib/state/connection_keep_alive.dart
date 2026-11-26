import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/keep_alive_service.dart';
import 'cup_connection_manager.dart';

/// 依水杯連線狀態開關 [KeepAliveService](Android 前景服務)。
///
/// 有記住的水杯、而且正在連線或自動重連中,就一直維持:螢幕關掉、切到別的 App
/// 時系統不會停掉 App,藍牙連線與背景重連都能繼續。使用者按「斷線」(回到 idle)才停。
/// Android 12 起背景不准啟動前景服務,啟動失敗時等 [onAppResumed] 再試。
class ConnectionKeepAlive {
  ConnectionKeepAlive({
    required this.manager,
    required this.service,
    this.operationTimeout = const Duration(seconds: 10),
  });

  final CupConnectionManager manager;
  final KeepAliveService service;

  /// 每個服務操作最多等多久;超過就當成失敗,不讓後面的操作一直排隊。
  final Duration operationTimeout;

  static const notificationTitle = '智慧水杯';

  /// 服務可能在跑:只要嘗試啟動過就算,直到確定停掉為止。和 [_started] 分開記,
  /// 因為啟動逾時、更新失敗時服務其實可能還在,不再需要時一定要呼叫 stop。
  bool _serviceMayBeRunning = false;

  /// 上一次啟動成功,之後可以直接更新通知內容。
  bool _started = false;
  String? _shownText;
  bool _disposed = false;

  /// 上一次排進佇列的內容;沒變就不再排(水杯資料每秒進來好幾次,都會通知一次)。
  bool _synced = false;
  String? _lastWanted;

  /// 依序執行 start/update/stop,避免狀態連續變化時互相交錯。
  Future<void> _queue = Future.value();

  void start() {
    manager.addListener(_sync);
    _sync();
  }

  /// App 回到前景:之前啟動失敗或沒關掉的再試一次,並補做只能在前景做的事。
  void onAppResumed() {
    if (_disposed) return;
    final wanted = _wantedText();
    _synced = true;
    _lastWanted = wanted;
    _enqueue(() => _applyOnResume(wanted));
  }

  /// 目前應該顯示的通知內容;null = 不需要維持。
  String? _wantedText() {
    final state = manager.state;
    final remembered = manager.rememberedDevice;
    final name = manager.connectingName ?? remembered?.name ?? '水杯';
    if (state == CupConnectionState.ready) return '已連線 · $name';
    // 配對中(掃描清單、連線新水杯)使用者正看著畫面,不需要維持,也不是「重新連線」
    if (manager.flow == CupFlow.pairing || remembered == null) return null;
    switch (state) {
      case CupConnectionState.idle:
      case CupConnectionState.ready:
        return null;
      case CupConnectionState.notFound:
        return '找不到 $name,背景重試中';
      case CupConnectionState.scanning:
      case CupConnectionState.connecting:
      case CupConnectionState.connected:
      case CupConnectionState.serviceDiscovered:
        return '重新連線中 · $name';
    }
  }

  void _sync() {
    if (_disposed) return;
    final wanted = _wantedText();
    if (_synced && wanted == _lastWanted) return;
    _synced = true;
    _lastWanted = wanted;
    _enqueue(() => _apply(wanted));
  }

  void _enqueue(Future<void> Function() operation) {
    _queue = _queue.then((_) => operation());
  }

  Future<void> _apply(String? wanted) async {
    if (wanted == null) return _stopService();
    if (!_started) return _startService(wanted);
    if (wanted != _shownText) await _updateService(wanted);
  }

  Future<void> _applyOnResume(String? wanted) async {
    if (wanted != null && _started) {
      try {
        final granted =
            await service.onAppForeground().timeout(operationTimeout);
        // 之前沒有通知權限時送出的通知不會顯示,拿到權限後要重送
        if (granted) _shownText = null;
      } catch (e, st) {
        debugPrint('[KeepAlive] 回到前景時的處理失敗:$e\n$st');
      }
    }
    await _apply(wanted);
  }

  // 以下三個操作失敗都不影響連線本身:記下來,下次狀態變化或回到前景時重試。

  Future<void> _startService(String text) async {
    // 先記:啟動逾時或丟例外時,服務其實可能已經起來了
    _serviceMayBeRunning = true;
    try {
      _started = await service
          .start(title: notificationTitle, text: text)
          .timeout(operationTimeout);
      if (!_started) debugPrint('[KeepAlive] 前景服務沒有啟動,App 回到前景時再試');
    } catch (e, st) {
      debugPrint('[KeepAlive] 前景服務啟動失敗:$e\n$st');
      _started = false;
    }
    _shownText = _started ? text : null;
  }

  Future<void> _updateService(String text) async {
    try {
      await service
          .update(title: notificationTitle, text: text)
          .timeout(operationTimeout);
      _shownText = text;
    } catch (e, st) {
      debugPrint('[KeepAlive] 更新前景服務通知失敗:$e\n$st');
      // 下次改走 start(服務還在的話它只會更新通知)
      _started = false;
      _shownText = null;
    }
  }

  Future<void> _stopService() async {
    _started = false;
    _shownText = null;
    if (!_serviceMayBeRunning) return;
    try {
      if (await service.stop().timeout(operationTimeout)) {
        _serviceMayBeRunning = false;
      } else {
        debugPrint('[KeepAlive] 前景服務沒有停掉,之後再試');
      }
    } catch (e, st) {
      debugPrint('[KeepAlive] 前景服務停止失敗,之後再試:$e\n$st');
    }
  }

  /// 停止維持並不再跟著狀態變化。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    manager.removeListener(_sync);
    _enqueue(_stopService);
    await _queue;
  }
}
