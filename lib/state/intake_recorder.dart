import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/intake_repository.dart';
import '../services/ble_service.dart';
import 'cup_connection_manager.dart';
import 'drink_detector.dart';

/// App 連線中自動記錄喝水/加水:把 [CupConnectionManager.packets] 餵給
/// [DrinkDetector],偵測到的事件寫入 [IntakeRepository](來源 appAuto)。
///
/// - 連線 Ready 後呼叫 [IntakeRepository.ensureCup],以該杯容量換算 mL;
///   容量在設定中被修改時(repo 通知)會重新讀取。
/// - 斷線:丟棄進行中的過程,但保留基準水位;同一個水杯重連後重新穩定,
///   會與斷線前的水位比較(例如水杯深度睡眠斷線、拿起來喝時才醒來重連)。
/// - 換成另一個水杯:完全重設。
/// - 事件時間使用封包到達手機的時間([clock]),不使用韌體時間戳。
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

  /// 尚未完成的寫入,測試可等待。
  final Set<Future<void>> _pending = {};

  /// 目前正在記錄的水杯 id。
  String? get cupId => _cupId;

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
    if (id == _cupId) return;

    if (id == null) {
      // 斷線:進行中的過程作廢,保留基準等同一杯重連。
      detector.reset(keepBaseline: true);
      _cupId = null;
      return;
    }

    detector.reset(keepBaseline: id == _lastCupId);
    _cupId = id;
    _lastCupId = id;
    _track(_ensureCup(id, manager.connectingName ?? ''));
  }

  Future<void> _ensureCup(String id, String name) async {
    final cup = await repo.ensureCup(id, name);
    if (_cupId == id) detector.capacityMl = cup.capacityMl;
  }

  void _onRepoChanged() {
    final id = _cupId;
    if (id == null) return;
    _track(repo.cup(id).then((cup) {
      if (cup != null && _cupId == id && cup.capacityMl > 0) {
        detector.capacityMl = cup.capacityMl;
      }
    }));
  }

  void _onPacket(CupDataPacket packet) {
    final id = _cupId;
    if (id == null) return;
    final at = _clock();
    final event = switch (packet) {
      WaterPacket() => detector.onWater(packet.fillFraction, at),
      PosePacket() => detector.onPose(packet.pose, packet.moving, at),
      StatePacket() => detector.onActivity(packet.activity, at),
      _ => null,
    };
    if (event != null) _track(_save(id, event));
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
