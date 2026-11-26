/// 讓 App 在背景時不被系統停掉,藍牙連線才能一直維持。
///
/// Android 用前景服務(通知列常駐一則通知),見 `foreground_keep_alive_service.dart`;
/// 其他平台不需要,用 [NoopKeepAliveService]。
library;

abstract interface class KeepAliveService {
  /// 開始維持;成功回傳 true。Android 12 起 App 在背景時不准啟動前景服務,會回傳 false。
  ///
  /// 丟出例外或回傳 false 時,服務仍然可能已經起來(例如等它啟動時逾時),
  /// 呼叫端不再需要時還是要呼叫 [stop]。
  Future<bool> start({required String title, required String text});

  /// 更新通知內容(已經在維持中才有效);失敗時丟出例外。
  Future<void> update({required String title, required String text});

  /// 停止維持。確定已經沒有在維持(本來就沒開也算)回傳 true;
  /// 停不掉回傳 false,呼叫端之後要再試。
  Future<bool> stop();

  /// App 回到前景時呼叫:補做只能在前景做的事(Android:請求通知權限)。
  /// 這次才取得通知權限時回傳 true,呼叫端要重送一次通知內容。
  Future<bool> onAppForeground();
}

/// 不需要前景服務的平台(桌面版、iOS 由系統的藍牙背景模式處理)。
class NoopKeepAliveService implements KeepAliveService {
  const NoopKeepAliveService();

  @override
  Future<bool> start({required String title, required String text}) async =>
      true;

  @override
  Future<void> update({required String title, required String text}) async {}

  @override
  Future<bool> stop() async => true;

  @override
  Future<bool> onAppForeground() async => false;
}
