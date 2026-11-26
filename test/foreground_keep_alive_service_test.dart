import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/services/foreground_keep_alive_service.dart';

/// 假的前景服務 plugin:記錄呼叫,可以指定每個操作的結果。
class _FakeApi implements ForegroundTaskApi {
  final List<String> calls = [];

  bool notificationGranted = true;

  /// 使用者在系統的詢問視窗按了什麼。
  bool userGrantsNotification = true;
  bool running = false;

  /// 不為 null 時該操作失敗(內容是錯誤)。
  Object? startError;
  Object? updateError;
  Object? stopError;

  int get initCalls => calls.where((c) => c == 'init').length;
  int get requestCalls => calls.where((c) => c == 'requestNotification').length;

  @override
  void init() => calls.add('init');

  @override
  Future<bool> hasNotificationPermission() async => notificationGranted;

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotification');
    notificationGranted = userGrantsNotification;
    return notificationGranted;
  }

  @override
  Future<bool> get isRunningService async => running;

  @override
  Future<Object?> startService({
    required String title,
    required String text,
  }) async {
    calls.add('start:$title|$text');
    if (startError == null) running = true;
    return startError;
  }

  @override
  Future<Object?> updateService({
    required String title,
    required String text,
  }) async {
    calls.add('update:$title|$text');
    return updateError;
  }

  @override
  Future<Object?> stopService() async {
    calls.add('stop');
    if (stopError == null) running = false;
    return stopError;
  }
}

void main() {
  late _FakeApi api;
  bool? bluetoothGranted;
  var bluetoothCheckThrows = false;
  var inForeground = true;

  AndroidForegroundKeepAliveService newService() =>
      AndroidForegroundKeepAliveService(
        api: api,
        hasBluetoothPermission: () async {
          if (bluetoothCheckThrows) throw StateError('檢查失敗');
          return bluetoothGranted;
        },
        isAppInForeground: () => inForeground,
      );

  setUp(() {
    api = _FakeApi();
    bluetoothGranted = true;
    bluetoothCheckThrows = false;
    inForeground = true;
  });

  group('start', () {
    test('啟動成功 → 回傳 true,帶標題與內容', () async {
      final ok = await newService().start(title: '智慧水杯', text: '已連線 · A');

      expect(ok, isTrue);
      expect(api.calls, ['init', 'start:智慧水杯|已連線 · A']);
    });

    test('只初始化一次', () async {
      final service = newService();
      await service.start(title: 't', text: 'a');
      await service.stop();
      await service.start(title: 't', text: 'b');

      expect(api.initCalls, 1);
    });

    test('沒有藍牙權限 → 不啟動(不用等原生端逾時),回傳 false', () async {
      bluetoothGranted = false;

      final ok = await newService().start(title: 't', text: 'a');

      expect(ok, isFalse);
      expect(api.calls.where((c) => c.startsWith('start:')), isEmpty);
      expect(api.requestCalls, 0);
    });

    test('查不到藍牙權限(null)→ 照樣嘗試啟動', () async {
      bluetoothGranted = null;

      expect(await newService().start(title: 't', text: 'a'), isTrue);
    });

    test('檢查藍牙權限時出錯 → 照樣嘗試啟動', () async {
      bluetoothCheckThrows = true;

      expect(await newService().start(title: 't', text: 'a'), isTrue);
    });

    test('原生端啟動失敗(ServiceRequestFailure)→ 回傳 false', () async {
      api.startError = StateError('ForegroundServiceStartNotAllowedException');

      expect(await newService().start(title: 't', text: 'a'), isFalse);
    });

    test('服務已經在跑 → 只更新通知,不重複啟動', () async {
      api.running = true;

      final ok = await newService().start(title: 't', text: 'a');

      expect(ok, isTrue);
      expect(api.calls, ['init', 'update:t|a']);
    });

    test('服務已經在跑但更新失敗 → 往上丟', () async {
      api
        ..running = true
        ..updateError = StateError('boom');

      await expectLater(
          newService().start(title: 't', text: 'a'), throwsStateError);
    });
  });

  group('通知權限', () {
    test('已經有權限 → 不詢問', () async {
      await newService().start(title: 't', text: 'a');

      expect(api.requestCalls, 0);
    });

    test('沒有權限、App 在前景 → 詢問一次;被拒絕也照樣啟動服務', () async {
      api
        ..notificationGranted = false
        ..userGrantsNotification = false;
      final service = newService();

      expect(await service.start(title: 't', text: 'a'), isTrue);
      await service.stop();
      await service.start(title: 't', text: 'a');

      expect(api.requestCalls, 1);
    });

    test('沒有權限、App 在背景 → 這次不詢問,回到前景時補問', () async {
      api.notificationGranted = false;
      inForeground = false;
      final service = newService();

      expect(await service.start(title: 't', text: 'a'), isTrue);
      expect(api.requestCalls, 0);

      inForeground = true;
      final granted = await service.onAppForeground();

      expect(api.requestCalls, 1);
      expect(granted, isTrue);
    });

    test('回到前景時使用者拒絕 → 回傳 false,之後不再問', () async {
      api
        ..notificationGranted = false
        ..userGrantsNotification = false;
      inForeground = false;
      final service = newService();
      await service.start(title: 't', text: 'a');
      inForeground = true;

      expect(await service.onAppForeground(), isFalse);
      expect(await service.onAppForeground(), isFalse);

      expect(api.requestCalls, 1);
    });

    test('回到前景時本來就有權限 → 不詢問,回傳 false(不是這次才拿到)', () async {
      final service = newService();
      await service.start(title: 't', text: 'a');

      expect(await service.onAppForeground(), isFalse);
      expect(api.requestCalls, 0);
    });
  });

  group('update', () {
    test('成功', () async {
      await newService().update(title: 't', text: 'b');

      expect(api.calls, ['update:t|b']);
    });

    test('失敗 → 往上丟', () async {
      api.updateError = StateError('ServiceNotStartedException');

      await expectLater(
          newService().update(title: 't', text: 'b'), throwsStateError);
    });
  });

  group('stop', () {
    test('服務在跑 → 停掉,回傳 true', () async {
      api.running = true;

      expect(await newService().stop(), isTrue);
      expect(api.calls, ['stop']);
    });

    test('服務沒在跑 → 不用停,回傳 true', () async {
      expect(await newService().stop(), isTrue);
      expect(api.calls, isEmpty);
    });

    test('停止失敗 → 回傳 false', () async {
      api
        ..running = true
        ..stopError = StateError('boom');

      expect(await newService().stop(), isFalse);
    });
  });
}
