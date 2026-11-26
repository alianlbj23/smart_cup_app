import 'dart:async';

import 'package:stut_food_intake_project/services/keep_alive_service.dart';

/// 記錄呼叫的 [KeepAliveService] 假實作。
class FakeKeepAliveService implements KeepAliveService {
  /// 每次呼叫,依序:`start:文字`、`update:文字`、`stop`。
  final List<String> calls = [];

  /// 設成 false 時 start() 回傳失敗(模擬 Android 不准在背景啟動前景服務)。
  bool startSucceeds = true;

  /// 不為 null 時,start() 要等它完成才會回傳(模擬原生端很慢)。
  Completer<void>? pendingStart;

  /// start() 丟出例外,但服務其實已經起來了(模擬等待服務啟動逾時)。
  bool startThrowsAfterStarting = false;

  /// update() 丟出例外。
  bool updateThrows = false;

  /// stop() 回傳 false,服務還在跑。
  bool stopFails = false;

  /// stop() 丟出例外,服務還在跑。
  bool stopThrows = false;

  /// 不為 null 時,stop() 要等它完成才會回傳。
  Completer<void>? pendingStop;

  /// onAppForeground() 的回傳值(這次是否新取得通知權限)。
  bool foregroundGrantsNotification = false;

  int foregroundCalls = 0;

  bool running = false;

  int get startCalls => calls.where((c) => c.startsWith('start:')).length;
  int get stopCalls => calls.where((c) => c == 'stop').length;

  @override
  Future<bool> start({required String title, required String text}) async {
    calls.add('start:$text');
    final pending = pendingStart;
    if (pending != null) {
      pendingStart = null;
      await pending.future;
    }
    if (startThrowsAfterStarting) {
      running = true;
      throw TimeoutException('前景服務啟動逾時');
    }
    running = startSucceeds;
    return startSucceeds;
  }

  @override
  Future<void> update({required String title, required String text}) async {
    calls.add('update:$text');
    if (updateThrows) throw StateError('更新前景服務通知失敗');
  }

  @override
  Future<bool> stop() async {
    calls.add('stop');
    final pending = pendingStop;
    if (pending != null) {
      pendingStop = null;
      await pending.future;
    }
    if (stopThrows) throw StateError('前景服務停止失敗');
    if (stopFails) return false;
    running = false;
    return true;
  }

  @override
  Future<bool> onAppForeground() async {
    foregroundCalls++;
    return foregroundGrantsNotification;
  }
}
