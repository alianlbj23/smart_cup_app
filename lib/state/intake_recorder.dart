import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/intake_repository.dart';
import '../services/ble_service.dart';
import 'cup_connection_manager.dart';
import 'drink_detector.dart';

/// 連線中自動記錄喝水/加水,寫入 [IntakeRepository]。事件來源依韌體版本二選一:
///
/// **韌體 ≥ 0.3.0([firmwareDetects])**:韌體是唯一的事件來源,App 自己的
/// [DrinkDetector] 關閉(否則同一口水會算兩次)。收到 DRINK_EVENT(0x07)→
/// 換算 mL → 存進資料庫(來源 firmware)→ 回 3-byte ACK。
/// - mL = |A − B| / 100 × 該水杯的容量(四捨五入)。
/// - `kind = 0` → 喝水,**一律 status = ok**(可能用吸管喝,沒有飲用姿態、過程
///   很久也照樣計入);`kind = 1` → 加水。
/// - `time_unknown`(或時間戳明顯不合理)→ 用收到的時間,並記下「時間為估計」。
/// - 重送的事件(seq + 時間戳 + A/B 相同)不會產生第二筆,但每次都回 ACK。
/// - 先存好才回 ACK:寫入失敗、或連線還沒 Ready(不知道容量)時不回,事件留在
///   水杯的 flash,韌體會重送。
///
/// **韌體 < 0.3.0**(原本的行為):把 [CupConnectionManager.packets] 餵給
/// [DrinkDetector],偵測到的事件寫入資料庫(來源 appAuto)。
/// - 斷線:丟棄進行中的過程,但保留基準水位;同一個水杯重連後重新穩定,
///   會與斷線前的水位比較(例如水杯深度睡眠斷線、拿起來喝時才醒來重連)。
/// - 換成另一個水杯:完全重設。
/// - 事件時間使用封包到達手機的時間([clock]),不使用韌體時間戳。
///
/// 兩種模式共通:連線 Ready 後呼叫 [IntakeRepository.ensureCup],以該杯容量換算 mL;
/// 容量在設定中被修改時(repo 通知)會重新讀取。Device Status 帶 BLE 位址時記到
/// `cups.bleAddress`(連結照護系統時當 `cup_hardware_id`)。
class IntakeRecorder {
  IntakeRecorder({
    required this.manager,
    required this.repo,
    DateTime Function()? clock,
    DrinkDetector? detector,
  })  : _clock = clock ?? DateTime.now,
        detector = detector ??
            DrinkDetector(capacityMl: IntakeRepository.defaultCupCapacityMl);

  final CupConnectionManager manager;
  final IntakeRepository repo;
  final DateTime Function() _clock;

  /// 使用中的偵測器(測試或除錯畫面可讀取狀態)。
  final DrinkDetector detector;

  StreamSubscription<CupDataPacket>? _sub;
  bool _started = false;

  /// 目前已 Ready 的水杯 id;未連線時為 null。
  String? _cupId;

  /// 最後一個連線過的水杯 id(斷線後仍保留,用來判斷重連的是不是同一杯)。
  String? _lastCupId;

  /// 這個水杯([_lastCupId])送過 DRINK_EVENT:就算沒讀到版本,也確定是由韌體偵測。
  bool _sawFirmwareEvent = false;

  /// 上一次判斷的 [firmwareDetects],用來在切換時重設偵測器。
  bool _firmwareMode = false;

  /// 目前容量(mL),換算韌體事件用;和 [detector] 的容量同步更新。
  int _capacityMl = IntakeRepository.defaultCupCapacityMl;

  /// 已經寫進資料庫的 BLE 位址(水杯 id → 位址),避免每次通知都寫一次。
  final Map<String, String> _savedBleAddress = {};

  /// 韌體事件依序處理(一筆存好、回完 ACK 才處理下一筆)。
  Future<void> _firmwareQueue = Future.value();

  /// 尚未完成的寫入,測試可等待。
  final Set<Future<void>> _pending = {};

  /// 韌體事件的時間戳早於這個時間(2024-01-01 UTC)視為沒對時,不採用。
  static const _minValidUnixSeconds = 1704067200;

  /// 韌體事件的時間戳比手機時間晚超過這麼多視為不合理,不採用。
  static const _maxFutureSkew = Duration(minutes: 10);

  /// 目前正在記錄的水杯 id。
  String? get cupId => _cupId;

  /// 連線中的水杯是否由韌體偵測喝水(Device Status 的版本 ≥ 0.3.0,或已經收過
  /// DRINK_EVENT)。true 時 [detector] 關閉,事件只來自韌體。
  bool get firmwareDetects =>
      _cupId != null &&
      (_sawFirmwareEvent ||
          (manager.deviceStatus?.firmwareDetectsDrinks ?? false));

  /// 開始監聽連線與封包。重複呼叫無效。
  void start() {
    if (_started) return;
    _started = true;
    manager.addListener(_onManagerChanged);
    repo.addListener(_onRepoChanged);
    _sub = manager.packets.listen(_onPacket);
    _onManagerChanged();
  }

  /// 等待目前所有寫入資料庫的動作完成。
  @visibleForTesting
  Future<void> flush() => Future.wait([..._pending]);

  void dispose() {
    if (!_started) return;
    _started = false;
    manager.removeListener(_onManagerChanged);
    repo.removeListener(_onRepoChanged);
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _onManagerChanged() {
    final id = manager.state == CupConnectionState.ready
        ? manager.activeDeviceId
        : null;
    if (id != _cupId) {
      if (id == null) {
        // 斷線:進行中的過程作廢,保留基準等同一杯重連。
        detector.reset(keepBaseline: true);
        _cupId = null;
        return;
      }
      if (id != _lastCupId) _sawFirmwareEvent = false;
      detector.reset(keepBaseline: id == _lastCupId);
      _cupId = id;
      _lastCupId = id;
      _firmwareMode = false;
      // 容量要先讀好,韌體事件才能換算 mL:排在韌體事件佇列的最前面。
      final name = manager.connectingName ?? '';
      _track(_enqueue(() => _ensureCup(id, name)));
    }
    if (id == null) return;
    _syncFirmwareMode();
    _saveBleAddress(id);
  }

  /// 剛變成「由韌體偵測」時重設 App 的偵測器,進行到一半的過程不會再產生事件。
  void _syncFirmwareMode() {
    final mode = firmwareDetects;
    if (mode == _firmwareMode) return;
    _firmwareMode = mode;
    if (mode) detector.reset(keepBaseline: false);
  }

  void _saveBleAddress(String id) {
    final address = manager.deviceStatus?.bleAddress;
    if (address == null || _savedBleAddress[id] == address) return;
    _savedBleAddress[id] = address;
    _track(_enqueue(() async {
      final cup = await repo.cup(id);
      if (cup != null && cup.bleAddress != address) {
        await repo.setCupBleAddress(id, address);
      }
    }).catchError((Object e) {
      // 沒寫成功:下次通知再試。
      _savedBleAddress.remove(id);
      throw e;
    }));
  }

  Future<void> _ensureCup(String id, String name) async {
    final cup = await repo.ensureCup(id, name);
    if (_cupId == id) _setCapacity(cup.capacityMl);
  }

  void _setCapacity(int capacityMl) {
    if (capacityMl <= 0) return;
    _capacityMl = capacityMl;
    detector.capacityMl = capacityMl;
  }

  void _onRepoChanged() {
    final id = _cupId;
    if (id == null) return;
    _track(repo.cup(id).then((cup) {
      if (cup != null && _cupId == id) _setCapacity(cup.capacityMl);
    }));
  }

  void _onPacket(CupDataPacket packet) {
    final id = _cupId;
    if (packet is DrinkEventPacket) {
      if (id == null) {
        // 連線還在初始化(還不知道是哪個水杯、容量多少):不存也不回 ACK,韌體等不到
        // ACK 會重送。
        debugPrint('[IntakeRecorder] 連線尚未就緒,先不處理 DRINK_EVENT '
            'seq ${packet.seq}(等韌體重送)');
        return;
      }
      _sawFirmwareEvent = true;
      _syncFirmwareMode();
      final receivedAt = _clock();
      _track(_enqueue(() => _onFirmwareEvent(id, packet, receivedAt)));
      return;
    }
    // 由韌體偵測時 App 不再自己判斷,否則同一次喝水會記兩筆。
    if (id == null || firmwareDetects) return;
    final at = _clock();
    final event = switch (packet) {
      WaterPacket() => detector.onWater(packet.fillFraction, at),
      PosePacket() => detector.onPose(packet.pose, packet.moving, at),
      StatePacket() => detector.onActivity(packet.activity, at),
      _ => null,
    };
    if (event != null) _track(_save(id, event));
  }

  /// 把 [job] 排進韌體事件佇列,前一個做完(不論成功失敗)才開始。
  Future<void> _enqueue(Future<void> Function() job) {
    final done = _firmwareQueue.then((_) => job());
    _firmwareQueue = done.catchError((Object _) {});
    return done;
  }

  /// 存一筆韌體事件並回 ACK。寫入失敗時丟出例外、不回 ACK。
  Future<void> _onFirmwareEvent(
    String cupId,
    DrinkEventPacket p,
    DateTime receivedAt,
  ) async {
    final kind = switch (p.kind) {
      FirmwareEventKind.drink => IntakeKind.drink,
      FirmwareEventKind.refill => IntakeKind.refill,
      FirmwareEventKind.unknown => null,
    };
    if (kind == null) {
      // 保留的種類:這一版 App 看不懂。照樣回 ACK,否則韌體一次只送一筆,會卡住後面的事件。
      debugPrint('[IntakeRecorder] 忽略未知種類的 DRINK_EVENT(seq ${p.seq})');
      await manager.ackDrinkEvent(p);
      return;
    }

    final timeTrusted = !p.timeUnknown &&
        p.timestamp >= _minValidUnixSeconds &&
        !p.time.isAfter(receivedAt.add(_maxFutureSkew));
    final capacityMl = _capacityMl;
    final result = await repo.addFirmwareEvent(
      cupId: cupId,
      dedupKey: p.dedupKey,
      kind: kind,
      ml: ((p.beforePercent - p.afterPercent).abs() / 100 * capacityMl).round(),
      startedAt: timeTrusted ? p.time : receivedAt,
      timeEstimated: !timeTrusted,
      capacityMl: capacityMl,
      levelBeforePct: p.beforePercent,
      levelAfterPct: p.afterPercent,
      sawDrinking: p.sawDrinking,
      tooLong: p.tooLong,
      seq: p.seq,
    );
    if (!result.created) {
      debugPrint('[IntakeRecorder] DRINK_EVENT seq ${p.seq} 已經存過,只回 ACK');
    }
    await manager.ackDrinkEvent(p);
  }

  Future<void> _save(String cupId, DetectedIntake e) async {
    await repo.addEvent(
      kind: e.kind,
      ml: e.ml,
      startedAt: e.startedAt,
      endedAt: e.endedAt,
      cupId: cupId,
      beforeMl: e.beforeMl,
      afterMl: e.afterMl,
      capacityMl: detector.capacityMl,
      source: IntakeSource.appAuto,
      status: e.status,
    );
  }

  void _track(Future<void> f) {
    final guarded = f.catchError((Object e, StackTrace st) {
      debugPrint('[IntakeRecorder] 寫入失敗:$e');
    });
    _pending.add(guarded);
    guarded.whenComplete(() => _pending.remove(guarded));
  }
}
