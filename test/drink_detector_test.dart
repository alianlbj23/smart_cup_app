import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/database.dart'
    show IntakeKind, IntakeStatus;
import 'package:stut_food_intake_project/services/ble_service.dart';
import 'package:stut_food_intake_project/state/drink_detector.dart';

/// 以「每秒一筆 POSE + 一筆 WATER」模擬韌體推送,時間完全由測試控制。
class _Sim {
  _Sim({int capacityMl = 350}) : d = DrinkDetector(capacityMl: capacityMl);

  final DrinkDetector d;
  final events = <DetectedIntake>[];
  static final t0 = DateTime(2026, 11, 23, 9);
  int sec = 0;

  DateTime get now => t0.add(Duration(seconds: sec));
  DateTime at(int s) => t0.add(Duration(seconds: s));

  int get capacity => d.capacityMl;
  double frac(num ml) => ml / capacity;

  void _add(DetectedIntake? e) {
    if (e != null) events.add(e);
  }

  /// 一秒:先送 POSE,再送 WATER(水量以 mL 表示,null 表示這秒沒有 WATER)。
  void tick(CupPose pose, {bool moving = false, num? ml}) {
    _add(d.onPose(pose, moving, now));
    if (ml != null) _add(d.onWater(frac(ml), now));
    sec++;
  }

  /// 直立靜止 [secs] 秒,水位 [ml]。
  void rest(num ml, {int secs = 5}) {
    for (var i = 0; i < secs; i++) {
      tick(CupPose.upright, ml: ml);
    }
  }

  /// 拿起來喝一口:傾斜 → 飲用中 → 傾斜 → 直立但移動中。傾斜時水位讀值是亂的。
  void sip({int drinkingSecs = 3}) {
    tick(CupPose.upright, moving: true, ml: 340);
    tick(CupPose.tilted, moving: true, ml: 20);
    for (var i = 0; i < drinkingSecs; i++) {
      tick(CupPose.drinking, moving: true, ml: i.isEven ? 5 : 349);
    }
    tick(CupPose.tilted, moving: true, ml: 300);
    tick(CupPose.upright, moving: true, ml: 80);
  }

  /// 拿起來移動,但沒有出現飲用中姿態(例如倒掉、加水、搬動)。
  void handle({CupPose via = CupPose.tilted, int secs = 3}) {
    tick(CupPose.upright, moving: true, ml: 10);
    for (var i = 0; i < secs; i++) {
      tick(via, moving: true, ml: 333);
    }
    tick(CupPose.upright, moving: true, ml: 1);
  }
}

void main() {
  test('剛連上:第一次穩定只建立基準,不產生事件', () {
    final s = _Sim();
    s.rest(200);
    expect(s.events, isEmpty);
    expect(s.d.baselineMl, 200);
  });

  test('沒有姿態前的水位讀值不採用', () {
    final s = _Sim();
    for (var i = 0; i < 5; i++) {
      s.d.onWater(s.frac(200), s.at(i));
    }
    expect(s.d.baselineMl, isNull);
  });

  test('一般喝一口:減少量、時間、前後水量正確,狀態 ok', () {
    final s = _Sim();
    s.rest(200);
    final liftAt = s.now;
    s.sip();
    final putDownAt = s.now;
    s.rest(150);

    final e = s.events.single;
    expect(e.kind, IntakeKind.drink);
    expect(e.status, IntakeStatus.ok);
    expect(e.ml, 50);
    expect(e.beforeMl, 200);
    expect(e.afterMl, 150);
    expect(e.startedAt, liftAt);
    // 放下後 3 秒(且至少 3 筆讀值)才算穩定
    expect(e.endedAt, putDownAt.add(const Duration(seconds: 3)));
    expect(s.d.baselineMl, 150);
    expect(s.d.inEpisode, isFalse);
  });

  test('連續喝好幾口 → 每口各一筆', () {
    final s = _Sim();
    s.rest(300);
    s.sip();
    s.rest(260);
    s.sip(drinkingSecs: 5);
    s.rest(180);
    s.sip();
    s.rest(165);

    expect(s.events.map((e) => e.ml), [40, 80, 15]);
    expect(s.events.every((e) => e.kind == IntakeKind.drink), isTrue);
    expect(s.events.every((e) => e.status == IntakeStatus.ok), isTrue);
    expect(s.events.map((e) => e.afterMl), [260, 180, 165]);
  });

  test('放下不到 3 秒又拿起 → 視為同一口,只算一次', () {
    final s = _Sim();
    s.rest(200);
    final liftAt = s.now;
    s.sip();
    s.rest(180, secs: 2); // 還沒穩定就又拿起來
    s.sip();
    s.rest(150);

    final e = s.events.single;
    expect(e.ml, 50);
    expect(e.startedAt, liftAt);
  });

  test('加水 → refill,狀態 ok', () {
    final s = _Sim();
    s.rest(50);
    s.handle();
    s.rest(330);

    final e = s.events.single;
    expect(e.kind, IntakeKind.refill);
    expect(e.status, IntakeStatus.ok);
    expect(e.ml, 280);
    expect(e.beforeMl, 50);
    expect(e.afterMl, 330);
  });

  test('水量減少但沒看到飲用中姿態 → drink,狀態 uncertain(可能倒掉)', () {
    final s = _Sim();
    s.rest(300);
    s.handle(via: CupPose.lying);
    s.rest(100);

    final e = s.events.single;
    expect(e.kind, IntakeKind.drink);
    expect(e.status, IntakeStatus.uncertain);
    expect(e.ml, 200);
  });

  test('變化低於門檻(10 mL)視為雜訊,但基準仍更新', () {
    final s = _Sim();
    s.rest(200);
    s.sip();
    s.rest(193); // 少 7 mL
    expect(s.events, isEmpty);
    expect(s.d.baselineMl, 193);

    s.handle();
    s.rest(200); // 多 7 mL
    expect(s.events, isEmpty);

    s.sip();
    s.rest(190); // 比最新基準 200 少 10 mL → 剛好達門檻
    expect(s.events.single.ml, 10);
  });

  test('傾斜中的亂讀值不影響;穩定期間偶發突波由中位數濾掉', () {
    final s = _Sim();
    s.rest(200);
    s.sip(); // sip() 期間的讀值在 1..349 mL 之間亂跳
    s.tick(CupPose.upright, ml: 150);
    s.tick(CupPose.upright, ml: 349); // 突波
    s.tick(CupPose.upright, ml: 150);
    s.tick(CupPose.upright, ml: 151);
    s.rest(150);

    final e = s.events.single;
    expect(e.afterMl, 150);
    expect(e.ml, 50);
    expect(s.d.baselineMl, 150);
  });

  test('直立但移動中(端著走)的讀值不採用', () {
    final s = _Sim();
    s.rest(200);
    for (var i = 0; i < 10; i++) {
      s.tick(CupPose.upright, moving: true, ml: 20);
    }
    expect(s.d.baselineMl, 200);
    s.rest(200);
    expect(s.events, isEmpty);
  });

  test('姿態未知也不算穩定', () {
    final s = _Sim();
    for (var i = 0; i < 10; i++) {
      s.tick(CupPose.unknown, ml: 200);
    }
    expect(s.d.baselineMl, isNull);
  });

  test('休眠中:沒有 POSE,最後姿態直立靜止時 WATER 直接視為穩定', () {
    final s = _Sim();
    s.rest(200);
    expect(s.d.onActivity(CupActivity.dozing, s.now), isNull);
    // 休眠中每 30 秒才一筆,緩慢漂移跟著基準走,不產生事件
    for (var i = 0; i < 4; i++) {
      s.sec += 30;
      expect(s.d.onWater(s.frac(198 - i), s.now), isNull);
    }
    // 基準為最近 5 筆(200, 198, 197, 196, 195)的中位數
    expect(s.d.baselineMl, 197);

    // 拿起杯子 → 喚醒;在下一筆 POSE 之前的 WATER 不採用
    s.sec += 600;
    final wokeAt = s.now;
    expect(s.d.onActivity(CupActivity.active, s.now), isNull);
    expect(s.d.onWater(s.frac(20), s.now), isNull);
    s.sec++;
    s.sip();
    s.rest(120);

    final e = s.events.single;
    expect(e.kind, IntakeKind.drink);
    expect(e.status, IntakeStatus.ok);
    expect(e.beforeMl, 197);
    expect(e.afterMl, 120);
    expect(e.startedAt, wokeAt);
  });

  test('休眠中但最後姿態不是直立靜止(例如倒著)→ 讀值不採用', () {
    final s = _Sim();
    s.rest(200);
    s.tick(CupPose.lying, ml: 30);
    s.d.onActivity(CupActivity.dozing, s.now);
    for (var i = 0; i < 3; i++) {
      s.sec += 30;
      expect(s.d.onWater(s.frac(30), s.now), isNull);
    }
    expect(s.d.baselineMl, 200);
    expect(s.d.inEpisode, isTrue);
  });

  test('連上時水杯正在休眠(補送最後姿態)→ 1 筆讀值即可建立基準', () {
    final s = _Sim();
    s.d.onActivity(CupActivity.dozing, s.now);
    s.d.onPose(CupPose.upright, false, s.now);
    s.d.onWater(s.frac(250), s.now);
    expect(s.d.baselineMl, 250);
  });

  test('reset(斷線/換杯):丟棄進行中的過程與基準,重新穩定只建立基準', () {
    final s = _Sim();
    s.rest(300);
    s.sip();
    expect(s.d.inEpisode, isTrue);
    s.d.reset();
    expect(s.d.inEpisode, isFalse);
    expect(s.d.baselineMl, isNull);

    s.rest(100);
    expect(s.events, isEmpty);
    expect(s.d.baselineMl, 100);
  });

  test('reset 後殘留的姿態不算數:要重新收到直立 POSE 才採用水位', () {
    final s = _Sim();
    s.rest(300);
    s.d.reset();
    for (var i = 0; i < 5; i++) {
      s.d.onWater(s.frac(100), s.at(100 + i));
    }
    expect(s.d.baselineMl, isNull);
  });

  test('reset(keepBaseline):同一杯重連後與斷線前的基準比較', () {
    final s = _Sim();
    s.rest(300);
    s.sip(); // 喝到一半斷線
    s.d.reset(keepBaseline: true);
    expect(s.d.baselineMl, 300);

    s.sec += 120;
    final reconnectedAt = s.now;
    s.rest(220);

    final e = s.events.single;
    expect(e.kind, IntakeKind.drink);
    expect(e.status, IntakeStatus.uncertain, reason: '重連後沒看到飲用中姿態');
    expect(e.ml, 80);
    expect(e.startedAt, reconnectedAt);
  });

  test('reset(keepBaseline):重連後有看到喝水 → ok;水量沒變 → 無事件', () {
    final s = _Sim();
    s.rest(300);
    s.d.reset(keepBaseline: true);
    s.rest(300);
    expect(s.events, isEmpty);

    s.d.reset(keepBaseline: true);
    s.sip();
    s.rest(250);
    expect(s.events.single.status, IntakeStatus.ok);
  });

  test('容量換算:同樣的比例變化依容量換成不同 mL,門檻也跟著變', () {
    // 0.02 的變化:350 mL 杯 = 7 mL(雜訊),1000 mL 杯 = 20 mL
    for (final (cap, expected) in [(350, null), (1000, 20)]) {
      final d = DrinkDetector(capacityMl: cap);
      final events = <DetectedIntake>[];
      var t = 0;
      DateTime at() => _Sim.t0.add(Duration(seconds: t++));
      void rest(double f) {
        for (var i = 0; i < 5; i++) {
          final now = at();
          for (final e in [
            d.onPose(CupPose.upright, false, now),
            d.onWater(f, now),
          ]) {
            if (e != null) events.add(e);
          }
        }
      }

      rest(0.50);
      d.onPose(CupPose.drinking, true, at());
      rest(0.48);
      expect(events.map((e) => e.ml).firstOrNull, expected, reason: '$cap mL');
    }
  });

  test('capacityMl 可隨時修改,下一筆事件即用新容量換算', () {
    final s = _Sim();
    s.rest(175); // 0.5
    s.d.capacityMl = 500;
    s.sip();
    s.rest(150); // 以 500 mL 換算 = 0.3
    final e = s.events.single;
    expect(e.beforeMl, 250);
    expect(e.afterMl, 150);
    expect(e.ml, 100);
  });

  test('過程超過 10 分鐘 → 仍產生事件但標為 uncertain', () {
    final s = _Sim();
    s.rest(300);
    s.tick(CupPose.drinking, moving: true, ml: 10);
    s.sec += 11 * 60;
    s.rest(200);
    final e = s.events.single;
    expect(e.kind, IntakeKind.drink);
    expect(e.status, IntakeStatus.uncertain);

    s.handle();
    s.sec += 11 * 60;
    s.rest(300);
    expect(s.events.last.kind, IntakeKind.refill);
    expect(s.events.last.status, IntakeStatus.uncertain);
  });

  test('穩定條件在兩筆封包之間滿足後又被拿起 → 以離開前的水位結算', () {
    final d = DrinkDetector(capacityMl: 100);
    final t0 = _Sim.t0;
    DateTime ms(int v) => t0.add(Duration(milliseconds: v));
    d.onPose(CupPose.upright, false, ms(0));
    for (var i = 0; i < 4; i++) {
      d.onWater(0.8, ms(1000 * i));
    }
    d.onPose(CupPose.drinking, true, ms(4000));
    d.onPose(CupPose.upright, false, ms(5000));
    d.onWater(0.5, ms(5000));
    d.onWater(0.5, ms(6000));
    d.onWater(0.5, ms(7000)); // 3 筆,但才穩定 2 秒
    final e = d.onPose(CupPose.tilted, true, ms(8100)); // 已穩定 3.1 秒
    expect(e?.ml, 30);
    expect(e?.endedAt, ms(8100));
    expect(d.inEpisode, isTrue, reason: '再次拿起 → 新過程');
  });
}
