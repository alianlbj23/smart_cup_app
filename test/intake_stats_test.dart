import 'package:flutter_test/flutter_test.dart';
import 'package:stut_food_intake_project/data/intake_repository.dart';
import 'package:stut_food_intake_project/state/intake_stats.dart';

var _seq = 0;

IntakeEvent ev(
  DateTime t,
  int ml, {
  IntakeKind kind = IntakeKind.drink,
  IntakeStatus status = IntakeStatus.ok,
}) =>
    IntakeEvent(
      id: 'e${_seq++}',
      drinkerId: 'me',
      kind: kind,
      ml: ml,
      startedAtMs: t.millisecondsSinceEpoch,
      tzOffsetMin: t.timeZoneOffset.inMinutes,
      localDay: dayKey(t),
      source: IntakeSource.manual,
      status: status,
      updatedAtMs: 0,
    );

DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 20, h, m);

final day = DateTime(2026, 11, 20);
// 「過去的日子」:現在是隔天中午。
final later = DateTime(2026, 11, 21, 12);

DayStats past(List<IntakeEvent> events, {int goal = 1500}) =>
    DayStats.fromEvents(events, day: day, goalMl: goal, now: later);

void main() {
  group('DayStats 基本', () {
    test('沒有喝水:總量 0、覆蓋 0/7、無集中時段、間隔為整個清醒時段', () {
      final s = past(const []);
      expect(s.totalMl, 0);
      expect(s.progress, 0);
      expect(s.metGoal, isFalse);
      expect(s.hourly, List.filled(24, 0));
      expect(s.slotsCovered, 0);
      expect(s.slotsEligible, 7);
      expect(s.peak, isNull);
      expect(s.peakShare, isNull);
      expect(s.longestGap!.start, at(6));
      expect(s.longestGap!.end, at(20));
      expect(s.longestGap!.ongoing, isFalse);
      expect(s.cumulative, [
        (time: day, ml: 0),
        (time: DateTime(2026, 11, 21), ml: 0),
      ]);
    });

    test('只計入正常的喝水:待確認、加水、倒掉、已刪除、別天都排除', () {
      final s = past([
        ev(at(9), 200),
        ev(at(10), 300, kind: IntakeKind.refill),
        ev(at(11), 80, status: IntakeStatus.uncertain),
        ev(at(12), 999, status: IntakeStatus.deleted),
        ev(at(13), 120, kind: IntakeKind.discard),
        ev(DateTime(2026, 11, 19, 9), 500), // 前一天
        ev(at(15), 300),
      ]);
      expect(s.totalMl, 500);
      expect(s.drinks.map((d) => d.ml), [200, 300]);
      expect(s.hourly[9], 200);
      expect(s.hourly[15], 300);
      expect(s.hourly.fold(0, (a, b) => a + b), 500);
    });

    test('進度、達標、累積階梯與理想進度', () {
      final s = past([ev(at(14), 900), ev(at(8), 600)], goal: 1500);
      expect(s.totalMl, 1500);
      expect(s.progress, 1.0);
      expect(s.metGoal, isTrue);
      expect(s.drinks.map((d) => d.time), [at(8), at(14)]); // 依時間排序
      expect(s.cumulative, [
        (time: day, ml: 0),
        (time: at(8), ml: 600),
        (time: at(14), ml: 1500),
        (time: DateTime(2026, 11, 21), ml: 1500),
      ]);
      expect(s.cumulativeAt(at(13)), 600);
      expect(s.idealAt(at(5)), 0);
      expect(s.idealAt(at(6)), 0);
      expect(s.idealAt(at(13)), 750);
      expect(s.idealAt(at(20)), 1500);
      expect(s.idealAt(at(23)), 1500);
    });
  });

  group('分布指標', () {
    test('集中在跨兩段的 2 小時內', () {
      final s = past([ev(at(13, 10), 300), ev(at(13, 40), 300), ev(at(14, 50), 400)]);
      // 13:10、13:40 在 12–14 段,14:50 在 14–16 段。
      expect(s.slotsCovered, 2);
      // 滑動視窗從 13:10 起涵蓋全部三次。
      expect(s.peak!.start, at(13, 10));
      expect(s.peak!.end, at(15, 10));
      expect(s.peak!.ml, 1000);
      expect(s.peakShare, 1.0);
      // 06:00 → 13:10(7:10)比 14:50 → 20:00(5:10)長。
      expect(s.longestGap!.start, at(6));
      expect(s.longestGap!.end, at(13, 10));
    });

    test('全部在同一個 2 小時時段內(覆蓋 1/7)', () {
      final s = past([ev(at(12, 5), 250), ev(at(12, 50), 250), ev(at(13, 55), 500)]);
      expect(s.slotsCovered, 1);
      expect(s.slotsEligible, 7);
      expect(s.slotMl, [0, 0, 0, 1000, 0, 0, 0]);
      expect(s.peakShare, 1.0);
      expect(s.longestGap!.start, at(6));
      expect(s.longestGap!.end, at(12, 5));
      expect(s.longestGap!.duration, const Duration(hours: 6, minutes: 5));
    });

    test('平均分散在每個時段', () {
      final s = past([for (var h = 7; h < 20; h += 2) ev(at(h), 200)]);
      expect(s.totalMl, 1400);
      expect(s.slotsCovered, 7);
      expect(s.peakShare, closeTo(1 / 7, 1e-9));
      expect(s.peak!.start, at(7)); // 同量取最早
      expect(s.longestGap!.duration, const Duration(hours: 2));
      expect(s.longestGap!.start, at(7));
      expect(s.longestGap!.end, at(9));
    });

    test('清醒時段外的喝水:計入總量與集中度,但不算覆蓋、不切斷間隔', () {
      final s = past([ev(at(5), 300), ev(at(21), 300), ev(at(10), 300)]);
      expect(s.totalMl, 900);
      expect(s.slotsCovered, 1);
      expect(s.peakShare, closeTo(1 / 3, 1e-9));
      // 06:00 → 10:00 為 4h,10:00 → 20:00 為 10h。
      expect(s.longestGap!.start, at(10));
      expect(s.longestGap!.end, at(20));
    });

    test('20:00 剛好不算清醒時段;06:00 整點算第一段', () {
      final s = past([ev(at(6), 100), ev(at(20), 100)]);
      expect(s.slotMl, [100, 0, 0, 0, 0, 0, 0]);
      expect(s.slotsCovered, 1);
      expect(s.longestGap!.start, at(6));
      expect(s.longestGap!.end, at(20));
    });

    test('最集中時段用滑動視窗:跨時段邊界的緊鄰兩口算在一起', () {
      final s = past([
        ev(at(9), 400),
        ev(at(13, 55), 300),
        ev(at(14, 5), 300),
      ]);
      // 固定時段只有 300(12–14)/300(14–16);滑動視窗抓到 600。
      expect(s.slotMl[3], 300);
      expect(s.slotMl[4], 300);
      expect(s.peak!.start, at(13, 55));
      expect(s.peak!.ml, 600);
      expect(s.peakShare, 0.6);
    });

    test('視窗不超過當天 24:00', () {
      final s = past([ev(at(23), 100)]);
      expect(s.peak!.end, DateTime(2026, 11, 21));
    });
  });

  group('今天(只過了一部分)', () {
    test('只算已開始的時段,間隔算到現在且標示進行中', () {
      final now = at(11, 30);
      final s = DayStats.fromEvents([ev(at(7), 200), ev(at(8, 30), 200)],
          day: day, goalMl: 1400, now: now);
      expect(s.isToday, isTrue);
      expect(s.slotsEligible, 3); // 06、08、10 已開始
      expect(s.slotsCovered, 2);
      expect(s.longestGap!.start, at(8, 30));
      expect(s.longestGap!.end, now);
      expect(s.longestGap!.ongoing, isTrue);
      expect(s.cumulative.last, (time: now, ml: 400));
      expect(s.idealAt(now), closeTo(550, 1e-9));
    });

    test('今天還沒到 06:00:沒有可算的時段與間隔', () {
      final s = DayStats.fromEvents([ev(at(5), 200)],
          day: day, goalMl: 1500, now: at(5, 30));
      expect(s.slotsEligible, 0);
      expect(s.slotsCovered, 0);
      expect(s.longestGap, isNull);
      expect(s.totalMl, 200);
      expect(s.peakShare, 1.0);
    });

    test('今天一口都沒喝:間隔從 06:00 到現在', () {
      final s = DayStats.fromEvents(const [],
          day: day, goalMl: 1500, now: at(9, 15));
      expect(s.longestGap!.duration, const Duration(hours: 3, minutes: 15));
      expect(s.longestGap!.ongoing, isTrue);
      expect(s.slotsEligible, 2);
    });

    test('今天 20:00 之後:間隔算到 20:00,不是進行中', () {
      final s = DayStats.fromEvents([ev(at(19), 200)],
          day: day, goalMl: 1500, now: at(22));
      expect(s.slotsEligible, 7);
      expect(s.longestGap!.start, at(6));
      expect(s.longestGap!.end, at(19));
      expect(s.longestGap!.ongoing, isFalse);
    });
  });

  group('PeriodStats', () {
    test('weekRange 週一到週日', () {
      // 2026-11-20 是週五。
      final w = PeriodStats.weekRange(DateTime(2026, 11, 20, 15));
      expect(w.from, DateTime(2026, 11, 16));
      expect(w.to, DateTime(2026, 11, 22));
      // 週日屬於同一週,週一是新的一週。
      expect(PeriodStats.weekRange(DateTime(2026, 11, 22)).from,
          DateTime(2026, 11, 16));
      expect(PeriodStats.weekRange(DateTime(2026, 11, 23)).from,
          DateTime(2026, 11, 23));
      // 跨月。
      final x = PeriodStats.weekRange(DateTime(2026, 12, 2));
      expect(x.from, DateTime(2026, 11, 30));
      expect(x.to, DateTime(2026, 12, 6));
    });

    test('monthRange', () {
      expect(PeriodStats.monthRange(DateTime(2026, 2, 10)),
          (from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 28)));
      expect(PeriodStats.monthRange(DateTime(2026, 12, 31)).to,
          DateTime(2026, 12, 31));
    });

    test('本週:平均只算到今天,未來的日子不列入', () {
      final w = PeriodStats.weekRange(DateTime(2026, 11, 18));
      final s = PeriodStats.fromTotals({
        DateTime(2026, 11, 16): 1500,
        DateTime(2026, 11, 17): 900,
        DateTime(2026, 11, 18): 600, // 今天
      }, from: w.from, to: w.to, goalMl: 1500, now: DateTime(2026, 11, 18, 10));
      expect(s.dayCount, 7);
      expect(s.elapsedDays, 3);
      expect(s.totalMl, 3000);
      expect(s.averageMl, 1000);
      expect(s.daysMetGoal, 1);
      expect(s.maxMl, 1500);
      expect(s.days.map((d) => d.isFuture),
          [false, false, false, true, true, true, true]);
      expect(s.days[5].ml, 0); // 缺的日子補 0
    });

    test('過去的月份:平均除以整月天數', () {
      final m = PeriodStats.monthRange(DateTime(2026, 2, 1));
      final s = PeriodStats.fromTotals({
        DateTime(2026, 2, 1): 1400,
        DateTime(2026, 2, 28): 1400,
      }, from: m.from, to: m.to, goalMl: 1400, now: DateTime(2026, 11, 23));
      expect(s.dayCount, 28);
      expect(s.elapsedDays, 28);
      expect(s.averageMl, 100);
      expect(s.daysMetGoal, 2);
    });

    test('整段在未來:平均 0', () {
      final w = PeriodStats.weekRange(DateTime(2026, 12, 7));
      final s = PeriodStats.fromTotals(const {},
          from: w.from, to: w.to, goalMl: 1500, now: DateTime(2026, 11, 23));
      expect(s.elapsedDays, 0);
      expect(s.averageMl, 0);
      expect(s.totalMl, 0);
    });
  });

  group('沒有每日目標(已連結照護系統但尚未設定)', () {
    final day = DateTime(2026, 11, 23);
    IntakeEvent drink(int hour, int ml) => IntakeEvent(
          id: 'g$hour',
          drinkerId: 'me',
          kind: IntakeKind.drink,
          ml: ml,
          startedAtMs: DateTime(2026, 11, 23, hour).millisecondsSinceEpoch,
          tzOffsetMin: 480,
          localDay: '2026-11-23',
          source: IntakeSource.manual,
          status: IntakeStatus.ok,
          updatedAtMs: 0,
        );

    test('DayStats:goalMl 為 null → 沒有達成率、不算達標、沒有理想進度', () {
      final s = DayStats.fromEvents([drink(9, 900), drink(13, 900)],
          day: day, goalMl: null, now: DateTime(2026, 11, 23, 15));
      expect(s.goalMl, isNull);
      expect(s.hasGoal, isFalse);
      expect(s.totalMl, 1800);
      expect(s.progress, 0);
      expect(s.metGoal, isFalse);
      expect(s.idealAt(DateTime(2026, 11, 23, 13)), 0);
      expect(s.idealAt(DateTime(2026, 11, 23, 22)), 0);
    });

    test('DayStats:有目標時 hasGoal 為 true', () {
      final s = DayStats.fromEvents([drink(9, 900)],
          day: day, goalMl: 1800, now: DateTime(2026, 11, 23, 15));
      expect(s.hasGoal, isTrue);
      expect(s.progress, 0.5);
    });

    test('PeriodStats:goalMl 為 null → 達標天數 0,累積與平均照算', () {
      final w = PeriodStats.weekRange(day);
      final s = PeriodStats.fromTotals({day: 2000},
          from: w.from, to: w.to, goalMl: null, now: DateTime(2026, 11, 23, 15));
      expect(s.goalMl, isNull);
      expect(s.hasGoal, isFalse);
      expect(s.daysMetGoal, 0);
      expect(s.totalMl, 2000);
      expect(s.averageMl, 2000);
    });
  });
}
