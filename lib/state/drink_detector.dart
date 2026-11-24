import '../data/database.dart' show IntakeKind, IntakeStatus;
import '../services/ble_service.dart' show CupActivity, CupPose;

/// [DrinkDetector] 偵測到的一筆水量變化(尚未寫入資料庫)。
class DetectedIntake {
  const DetectedIntake({
    required this.kind,
    required this.ml,
    required this.startedAt,
    required this.endedAt,
    required this.beforeMl,
    required this.afterMl,
    required this.status,
  });

  /// [IntakeKind.drink](水量減少)或 [IntakeKind.refill](水量增加)。
  final IntakeKind kind;

  /// 變化量(mL),一律為正數。
  final int ml;

  /// 杯子離開穩定狀態(被拿起、傾斜、移動)的時間。
  final DateTime startedAt;

  /// 杯子放回並重新穩定的時間。
  final DateTime? endedAt;

  /// 變化前 / 後的水量(mL)。
  final int beforeMl;
  final int afterMl;

  /// 以下情況為 [IntakeStatus.uncertain],由使用者在 UI 確認:
  /// - 水量減少但沒看到「飲用中」姿態(可能是倒掉);
  /// - 水量增加但過程中看到「飲用中」姿態(可能喝了又裝水,喝的量被抵掉);
  /// - 過程太久。
  final IntakeStatus status;

  @override
  String toString() => 'DetectedIntake(${kind.name} $ml mL, '
      '$beforeMl→$afterMl, ${status.name}, $startedAt–$endedAt)';
}

/// 從 WATER / POSE / STATE 封包偵測喝水與加水。純 Dart,時間一律由呼叫端傳入。
///
/// 電容式水位在杯子傾斜或晃動時不可信,因此只在杯子「直立且靜止」持續
/// [stableDuration] 以上(稱為「穩定」)時才採用水位,取穩定期間最近
/// [medianWindow] 筆讀值的中位數作為「穩定水位」。
///
/// - 穩定中:基準水位 A 持續跟著穩定水位更新(緩慢漂移不會變成事件)。
/// - 離開穩定(傾斜/飲用中/倒下/移動/姿態未知/從休眠喚醒):開始一段過程,
///   記錄期間是否出現過 [CupPose.drinking]。
/// - 再次穩定得到水位 B:
///   - A − B ≥ [minChangeMl]:喝水;有看到飲用中姿態 → ok,否則 uncertain(可能是倒掉)。
///   - B − A ≥ [minChangeMl]:加水,ok。
///   - 其他:視為雜訊,不產生事件。
///   - 不論結果,基準都更新為 B。
///   - 過程超過 [maxEpisodeDuration](例如杯子被帶著走很久)仍會產生事件,
///     但一律標為 uncertain,交給使用者確認。
/// - 尚無基準(剛連上)時,第一次穩定只建立基準,不產生事件。
/// - 休眠中韌體不送 POSE:只要最後已知的姿態是直立且靜止,休眠中的 WATER
///   讀值直接視為穩定(不需等 [stableDuration] 與 [minSettledReadings])。
class DrinkDetector {
  DrinkDetector({
    required int capacityMl,
    this.minChangeMl = 10,
    this.stableDuration = const Duration(seconds: 3),
    this.minSettledReadings = 3,
    this.medianWindow = 5,
    this.maxEpisodeDuration = const Duration(minutes: 10),
  })  : assert(capacityMl > 0),
        assert(minSettledReadings >= 1),
        assert(medianWindow >= 1),
        _capacityMl = capacityMl;

  /// 低於此變化量(mL)視為雜訊。
  final double minChangeMl;

  /// 直立且靜止持續多久才算穩定。
  final Duration stableDuration;

  /// 活動中至少要有幾筆穩定期間的讀值才採用(休眠中 1 筆即可)。
  final int minSettledReadings;

  /// 穩定水位取最近幾筆讀值的中位數。
  final int medianWindow;

  /// 單次過程(離開穩定 → 重新穩定)的合理上限;超過時事件標為 uncertain。
  final Duration maxEpisodeDuration;

  int _capacityMl;

  /// 水杯容量(mL),用來把水量比例換算成 mL。可隨時修改,下一筆事件即生效。
  int get capacityMl => _capacityMl;
  set capacityMl(int value) {
    assert(value > 0);
    _capacityMl = value;
  }

  /// 最後已知姿態是否為直立且靜止;尚未收到 POSE 時為 false。
  bool _still = false;
  DateTime? _stillSince;

  /// 本次靜止期間收到的水量比例(最多 [medianWindow] 筆)。
  final List<double> _readings = [];
  bool _dozing = false;

  /// 基準水位 A(水量比例);尚未穩定過時為 null。
  double? _baseline;

  /// 進行中的過程開始時間;沒有過程時為 null。
  DateTime? _episodeStart;
  bool _sawDrinking = false;

  /// [reset] 保留基準後,下一筆輸入即開始一段過程。
  bool _episodePending = false;

  /// 目前的基準水位(mL,四捨五入);尚未建立時為 null。
  int? get baselineMl => _baseline == null ? null : _toMl(_baseline!);

  /// 是否有尚未結束的過程(杯子被拿起還沒放回穩定)。
  bool get inEpisode => _episodeStart != null || _episodePending;

  /// 收到一筆水量比例(0..1)。
  DetectedIntake? onWater(double fraction, DateTime at) {
    _startPendingEpisode(at);
    if (!_still) return null; // 傾斜/移動中的讀值不可信,直接丟棄
    _readings.add(fraction.clamp(0.0, 1.0));
    if (_readings.length > medianWindow) _readings.removeAt(0);
    return _evaluate(at);
  }

  /// 收到一筆姿態分類。
  DetectedIntake? onPose(CupPose pose, bool moving, DateTime at) {
    _startPendingEpisode(at);
    final still = pose == CupPose.upright && !moving;
    if (!still) {
      final event = _leaveStill(at);
      if (pose == CupPose.drinking && _episodeStart != null) {
        _sawDrinking = true;
      }
      return event;
    }
    if (!_still) {
      _still = true;
      _stillSince = at;
      _readings.clear();
    }
    return _evaluate(at);
  }

  /// 收到水杯活動狀態。從休眠喚醒代表杯子被動到了:在下一筆 POSE 之前
  /// 不再相信水位。
  DetectedIntake? onActivity(CupActivity activity, DateTime at) {
    _startPendingEpisode(at);
    if (activity == CupActivity.dozing) {
      _dozing = true;
      return _evaluate(at);
    }
    if (!_dozing) return null;
    _dozing = false;
    return _leaveStill(at);
  }

  /// 斷線或換杯時呼叫:丟棄進行中的過程與姿態資訊。
  ///
  /// [keepBaseline] 為 true(同一個水杯斷線後重連)時保留基準水位 A,
  /// 下一筆輸入即視為一段新過程的開始,重新穩定後與 A 比較;斷線期間
  /// 沒看到飲用中姿態,水量減少就會標為 uncertain。
  void reset({bool keepBaseline = false}) {
    _still = false;
    _stillSince = null;
    _readings.clear();
    _dozing = false;
    _episodeStart = null;
    _sawDrinking = false;
    if (!keepBaseline) _baseline = null;
    _episodePending = keepBaseline && _baseline != null;
  }

  void _startPendingEpisode(DateTime at) {
    if (!_episodePending) return;
    _episodePending = false;
    _episodeStart = at;
    _sawDrinking = false;
  }

  /// 杯子不再直立靜止。若離開前已達穩定條件(例如穩定時間剛好在兩筆封包
  /// 之間滿足),先以當時水位結算,再開始新過程。
  DetectedIntake? _leaveStill(DateTime at) {
    final event = _evaluate(at);
    if (_baseline != null && _episodeStart == null) {
      _episodeStart = at;
      _sawDrinking = false;
    }
    _still = false;
    _stillSince = null;
    _readings.clear();
    return event;
  }

  bool _isSettled(DateTime at) {
    if (!_still || _readings.isEmpty) return false;
    if (_dozing) return true;
    return _readings.length >= minSettledReadings &&
        at.difference(_stillSince!) >= stableDuration;
  }

  DetectedIntake? _evaluate(DateTime at) {
    if (!_isSettled(at)) return null;
    final level = _median(_readings);
    final before = _baseline;
    final start = _episodeStart;
    _baseline = level;
    if (before == null || start == null) return null; // 建立/追蹤基準

    final sawDrinking = _sawDrinking;
    _episodeStart = null;
    _sawDrinking = false;

    final tooLong = at.difference(start) > maxEpisodeDuration;
    final deltaMl = (level - before) * _capacityMl;
    // 容許浮點誤差,剛好等於門檻的變化也算數。
    final threshold = minChangeMl - 1e-6;
    final IntakeKind kind;
    final IntakeStatus status;
    if (-deltaMl >= threshold) {
      kind = IntakeKind.drink;
      status = sawDrinking && !tooLong ? IntakeStatus.ok : IntakeStatus.uncertain;
    } else if (deltaMl >= threshold) {
      kind = IntakeKind.refill;
      // 過程中出現過「飲用中」:可能先喝再裝水(或裝完先喝一口)才放回,
      // 只看得到淨增加,喝的量算不出來 → 待確認,讓使用者補記喝了多少。
      status = tooLong || sawDrinking ? IntakeStatus.uncertain : IntakeStatus.ok;
    } else {
      return null; // 雜訊
    }
    return DetectedIntake(
      kind: kind,
      ml: deltaMl.abs().round(),
      startedAt: start,
      endedAt: at,
      beforeMl: _toMl(before),
      afterMl: _toMl(level),
      status: status,
    );
  }

  int _toMl(double fraction) => (fraction * _capacityMl).round();

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
