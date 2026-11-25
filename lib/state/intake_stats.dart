import '../data/intake_repository.dart';

/// 清醒時段的開始(06:00):理想進度從這裡由 0 起算。
const wakingStartHour = 6;

/// 清醒時段的結束(20:00):理想進度在這裡達到每日目標。
const wakingEndHour = 20;

/// 時段覆蓋用的時段長度(小時):06–20 切成 7 段。
const slotHours = 2;

/// 清醒時段內的時段數(7)。
const wakingSlotCount = (wakingEndHour - wakingStartHour) ~/ slotHours;

/// 最集中時段的視窗長度。
const peakWindow = Duration(hours: 2);

/// 一次喝水。
class DrinkPoint {
  const DrinkPoint({required this.time, required this.ml, this.id});

  final DateTime time;
  final int ml;

  /// 對應的事件 id;純計算時可為 null。
  final String? id;

  @override
  String toString() => 'DrinkPoint(${time.toIso8601String()}, $ml)';
}

/// 累積曲線上的一點:到 [time] 為止累積 [ml]。
typedef CumulativePoint = ({DateTime time, int ml});

/// 最長未喝水間隔。
class DrinkGap {
  const DrinkGap({required this.start, required this.end, this.ongoing = false});

  final DateTime start;
  final DateTime end;

  /// 間隔一直延續到「現在」(今天,且之後還沒喝)。
  final bool ongoing;

  Duration get duration => end.difference(start);

  @override
  String toString() =>
      'DrinkGap(${start.toIso8601String()} → ${end.toIso8601String()}'
      '${ongoing ? ', ongoing' : ''})';
}

/// 最集中的 2 小時視窗。
class PeakWindow {
  const PeakWindow({
    required this.start,
    required this.end,
    required this.ml,
    required this.share,
  });

  /// 視窗起點 = 視窗內第一次喝水的時間。
  final DateTime start;

  /// 視窗終點 = [start] + 2 小時(不超過當天 24:00)。
  final DateTime end;

  /// 視窗內的飲水量。
  final int ml;

  /// 占當日總量的比例(0–1)。
  final double share;
}

/// 單日統計。純計算,不碰資料庫,方便測試。
///
/// 只有 [IntakeEventX.countsAsIntake](喝水且狀態正常)的事件會計入;
/// 加水、倒掉、待確認與已刪除的事件一律忽略。
class DayStats {
  DayStats._({
    required this.day,
    required this.goalMl,
    required this.now,
    required this.drinks,
  });

  /// 由當天的事件計算統計。
  ///
  /// [events] 通常是 `repo.eventsOnDay(day)` 的結果;不屬於 [day]
  /// (依 `localDay`)的事件會被略過。[now] 用來判斷「今天」已經過了多少:
  /// 未來的時段不列入時段覆蓋、最長間隔只算到現在。
  factory DayStats.fromEvents(
    List<IntakeEvent> events, {
    required DateTime day,
    required int? goalMl,
    required DateTime now,
  }) {
    final start = startOfDay(day);
    final key = dayKey(start);
    final drinks = [
      for (final e in events)
        if (e.countsAsIntake && e.localDay == key)
          DrinkPoint(time: e.startedAt, ml: e.ml, id: e.id),
    ]..sort((a, b) => a.time.compareTo(b.time));
    return DayStats._(day: start, goalMl: goalMl, now: now, drinks: drinks);
  }

  /// 當天 00:00。
  final DateTime day;

  /// 每日目標(mL)。null = 沒有目標(已連結照護系統但照護系統尚未設定):
  /// 不算達成率、不畫理想進度,不可以拿預設值來代替。
  final int? goalMl;
  final DateTime now;

  /// 有沒有可以拿來比較的目標。
  bool get hasGoal => (goalMl ?? 0) > 0;

  /// 當天每一次喝水,依時間排序。
  final List<DrinkPoint> drinks;

  DateTime get dayEnd => DateTime(day.year, day.month, day.day + 1);
  DateTime get wakingStart => DateTime(day.year, day.month, day.day, wakingStartHour);
  DateTime get wakingEnd => DateTime(day.year, day.month, day.day, wakingEndHour);

  bool get isToday => dayKey(now) == dayKey(day);
  bool get isFuture => day.isAfter(now);

  /// 統計截止時間:今天為現在,過去的日子為當天 24:00。
  DateTime get cutoff => isToday ? now : (isFuture ? day : dayEnd);

  /// 當日總飲水量。
  late final int totalMl = drinks.fold(0, (s, d) => s + d.ml);

  /// 達成率(可超過 1)。沒有目標時為 0。
  double get progress => hasGoal ? totalMl / goalMl! : 0;

  bool get metGoal => hasGoal && totalMl >= goalMl!;

  /// 每小時飲水量,索引 0–23。
  late final List<int> hourly = () {
    final bins = List<int>.filled(24, 0);
    for (final d in drinks) {
      bins[d.time.hour] += d.ml;
    }
    return bins;
  }();

  /// 累積階梯曲線:從 00:00 的 0 開始,每次喝水跳升一階,
  /// 最後一點在 [cutoff](今天)或 24:00(過去的日子)。
  late final List<CumulativePoint> cumulative = () {
    final pts = <CumulativePoint>[(time: day, ml: 0)];
    var sum = 0;
    for (final d in drinks) {
      sum += d.ml;
      pts.add((time: d.time, ml: sum));
    }
    final end = cutoff.isBefore(day) ? day : cutoff;
    if (pts.last.time.isBefore(end)) pts.add((time: end, ml: sum));
    return pts;
  }();

  /// [t] 時的理想累積量:06:00 為 0,直線上升到 20:00 達到目標,之後持平。
  /// 沒有目標時為 0。
  double idealAt(DateTime t) {
    final goal = goalMl;
    if (goal == null || goal <= 0 || !t.isAfter(wakingStart)) return 0;
    if (!t.isBefore(wakingEnd)) return goal.toDouble();
    final span = wakingEnd.difference(wakingStart).inSeconds;
    return goal * t.difference(wakingStart).inSeconds / span;
  }

  /// [t] 時(含)實際的累積量。
  int cumulativeAt(DateTime t) =>
      drinks.where((d) => !d.time.isAfter(t)).fold(0, (s, d) => s + d.ml);

  // ------------------------------------------------------------ 分布指標

  /// 清醒時段第 [i] 段(0–6)的起點。
  DateTime slotStart(int i) =>
      DateTime(day.year, day.month, day.day, wakingStartHour + i * slotHours);

  /// 每個 2 小時時段(06–08 … 18–20)的飲水量。
  late final List<int> slotMl = [
    for (var i = 0; i < wakingSlotCount; i++)
      drinks
          .where((d) =>
              !d.time.isBefore(slotStart(i)) && d.time.isBefore(slotStart(i + 1)))
          .fold(0, (s, d) => s + d.ml),
  ];

  /// 時段是否已開始(可列入覆蓋率):過去的日子全部 7 段;
  /// 今天只算起點不晚於現在的時段;未來的日子都不算。
  bool slotEligible(int i) => !slotStart(i).isAfter(cutoff) && !isFuture;

  /// 時段覆蓋的分母:已開始的時段數。
  int get slotsEligible =>
      [for (var i = 0; i < wakingSlotCount; i++) slotEligible(i)]
          .where((x) => x)
          .length;

  /// 時段覆蓋的分子:已開始且有喝水的時段數。
  int get slotsCovered => [
        for (var i = 0; i < wakingSlotCount; i++)
          slotEligible(i) && slotMl[i] > 0
      ].where((x) => x).length;

  /// 最集中時段:滑動 2 小時視窗,起點對齊每一次喝水,
  /// 取視窗 [起點, 起點 + 2h) 內總量最大者(同量取較早)。
  /// 以全天的喝水計算(含清醒時段外),沒有喝水時為 null。
  ///
  /// 選滑動視窗而非固定時段,是為了不讓 13:55 與 14:05 這種緊鄰的兩口
  /// 因為剛好跨過時段邊界而被拆開,低估集中程度。
  late final PeakWindow? peak = () {
    if (drinks.isEmpty || totalMl <= 0) return null;
    PeakWindow? best;
    for (var i = 0; i < drinks.length; i++) {
      final start = drinks[i].time;
      final end = start.add(peakWindow);
      var ml = 0;
      for (var j = i; j < drinks.length && drinks[j].time.isBefore(end); j++) {
        ml += drinks[j].ml;
      }
      if (best == null || ml > best.ml) {
        best = PeakWindow(
          start: start,
          end: end.isAfter(dayEnd) ? dayEnd : end,
          ml: ml,
          share: ml / totalMl,
        );
      }
    }
    return best;
  }();

  /// 最集中時段占比(0–1);沒有喝水時為 null。
  double? get peakShare => peak?.share;

  /// 最長未喝水間隔,只看清醒時段:
  /// 相鄰兩次喝水之間,加上 06:00 → 第一次喝水、最後一次喝水 → min(現在, 20:00)。
  /// 清醒時段外的喝水不當作分隔點。
  ///
  /// 今天尚未到 06:00(或未來的日子)時為 null;整天沒喝水時為
  /// 06:00 → min(現在, 20:00)。同長度取較早的一段。
  late final DrinkGap? longestGap = () {
    final end = cutoff.isAfter(wakingEnd) ? wakingEnd : cutoff;
    if (!end.isAfter(wakingStart)) return null;
    final marks = <DateTime>[
      wakingStart,
      for (final d in drinks)
        if (d.time.isAfter(wakingStart) && d.time.isBefore(end)) d.time,
      end,
    ];
    DrinkGap? best;
    for (var i = 1; i < marks.length; i++) {
      final g = DrinkGap(
        start: marks[i - 1],
        end: marks[i],
        ongoing: isToday && i == marks.length - 1 && end == now,
      );
      if (best == null || g.duration > best.duration) best = g;
    }
    return best;
  }();
}

// ---------------------------------------------------------------- 週 / 月

/// 一天的總量,週/月長條圖用。
class DayTotal {
  const DayTotal({required this.day, required this.ml, required this.isFuture});

  final DateTime day;
  final int ml;

  /// 今天之後的日子:不畫長條、不列入平均。
  final bool isFuture;
}

/// 一段期間(週或月)的統計。
class PeriodStats {
  PeriodStats._({
    required this.from,
    required this.to,
    required this.goalMl,
    required this.days,
  });

  /// 由 `repo.dailyTotals(from, to)` 的結果計算。缺少的日子視為 0。
  factory PeriodStats.fromTotals(
    Map<DateTime, int> totals, {
    required DateTime from,
    required DateTime to,
    required int? goalMl,
    required DateTime now,
  }) {
    final byKey = {for (final e in totals.entries) dayKey(e.key): e.value};
    final today = startOfDay(now);
    final days = <DayTotal>[];
    for (var d = startOfDay(from);
        !d.isAfter(startOfDay(to));
        d = DateTime(d.year, d.month, d.day + 1)) {
      days.add(DayTotal(
        day: d,
        ml: byKey[dayKey(d)] ?? 0,
        isFuture: d.isAfter(today),
      ));
    }
    return PeriodStats._(from: startOfDay(from), to: startOfDay(to), goalMl: goalMl, days: days);
  }

  /// 包含 [d] 的那一週(週一到週日)。
  static ({DateTime from, DateTime to}) weekRange(DateTime d) {
    final day = startOfDay(d);
    final monday = DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
    return (from: monday, to: DateTime(monday.year, monday.month, monday.day + 6));
  }

  /// 包含 [d] 的那個月(1 日到月底)。
  static ({DateTime from, DateTime to}) monthRange(DateTime d) =>
      (from: DateTime(d.year, d.month, 1), to: DateTime(d.year, d.month + 1, 0));

  final DateTime from;
  final DateTime to;

  /// 每日目標(mL);null = 沒有目標(照護系統尚未設定),不算達標天數、不畫目標線。
  final int? goalMl;
  final List<DayTotal> days;

  /// 有沒有可以拿來比較的目標。
  bool get hasGoal => (goalMl ?? 0) > 0;

  /// 期間的天數(週 7、月 28–31)。
  int get dayCount => days.length;

  /// 已經過的天數(到今天為止,含今天)。
  int get elapsedDays => days.where((d) => !d.isFuture).length;

  int get totalMl => days.fold(0, (s, d) => s + d.ml);

  /// 日平均 = 總量 ÷ 已經過的天數(含今天,不含未來的日子)。
  /// 整段都在未來時為 0。今天還沒結束,所以當天早上的平均會偏低。
  double get averageMl => elapsedDays == 0 ? 0 : totalMl / elapsedDays;

  /// 達標天數:總量 ≥ 目標的日子。沒有目標時為 0。
  int get daysMetGoal =>
      hasGoal ? days.where((d) => d.ml >= goalMl!).length : 0;

  int get maxMl => days.fold(0, (m, d) => d.ml > m ? d.ml : m);
}
