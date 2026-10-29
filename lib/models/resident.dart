/// 一筆飲水紀錄。
class IntakeEntry {
  const IntakeEntry({required this.time, required this.ml});

  final DateTime time;
  final int ml;

  Map<String, dynamic> toJson() =>
      {'t': time.millisecondsSinceEpoch, 'ml': ml};

  factory IntakeEntry.fromJson(Map<String, dynamic> json) => IntakeEntry(
        time: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
        ml: json['ml'] as int,
      );
}

/// 住民(長者)資料與其配對的水杯。
class Resident {
  Resident({
    required this.id,
    required this.name,
    required this.room,
    required this.age,
    required this.goalMl,
    List<String>? tags,
    this.cupId,
    this.cupName,
    List<IntakeEntry>? intakes,
  })  : tags = tags ?? [],
        intakes = intakes ?? [];

  final String id;
  String name;

  /// 房號/床號,例如 A112。
  String room;
  int age;

  /// 每日飲水目標(mL)。
  int goalMl;

  /// 照護註記,例如「高血壓」。
  List<String> tags;

  /// 配對水杯的 BLE deviceId;null 表示尚未配對。
  String? cupId;
  String? cupName;

  /// 依時間排序的飲水紀錄(含歷史日期)。
  final List<IntakeEntry> intakes;

  bool get hasCup => cupId != null;

  List<IntakeEntry> entriesOn(DateTime day) =>
      intakes.where((e) => isSameDay(e.time, day)).toList();

  int totalOn(DateTime day) =>
      intakes.fold(0, (sum, e) => isSameDay(e.time, day) ? sum + e.ml : sum);

  /// 當日達成率(可超過 1)。
  double progressOn(DateTime day) => goalMl <= 0 ? 0 : totalOn(day) / goalMl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'room': room,
        'age': age,
        'goalMl': goalMl,
        'tags': tags,
        'cupId': cupId,
        'cupName': cupName,
        'intakes': [for (final e in intakes) e.toJson()],
      };

  factory Resident.fromJson(Map<String, dynamic> json) => Resident(
        id: json['id'] as String,
        name: json['name'] as String,
        room: json['room'] as String? ?? '',
        age: json['age'] as int? ?? 0,
        goalMl: json['goalMl'] as int? ?? 1500,
        tags: [...?(json['tags'] as List?)?.cast<String>()],
        cupId: json['cupId'] as String?,
        cupName: json['cupName'] as String?,
        intakes: [
          for (final e in (json['intakes'] as List? ?? const []))
            IntakeEntry.fromJson((e as Map).cast<String, dynamic>()),
        ],
      );
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 飲水時程:白天 06:00–20:00 平均分配(少量多次、夜間不補)。
class HydrationSchedule {
  HydrationSchedule._();

  static const startHour = 6;
  static const endHour = 20;

  /// 落後時程超過此比例即需要提醒。
  static const behindThreshold = 0.15;

  /// [now] 當下應達成的目標比例(0–1)。
  static double expectedFraction(DateTime now) {
    final hours = now.hour + now.minute / 60;
    return ((hours - startHour) / (endHour - startHour))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static bool isBehind(Resident r, DateTime now) =>
      r.progressOn(now) < expectedFraction(now) - behindThreshold;

  static bool isOnTrack(Resident r, DateTime now) =>
      r.progressOn(now) >= expectedFraction(now);

  /// 落後時程的毫升數(未落後為 0)。
  static int lagMl(Resident r, DateTime now) {
    final lag = (expectedFraction(now) * r.goalMl).round() - r.totalOn(now);
    return lag > 0 ? lag : 0;
  }

  /// 建議現在補充的量:落後量的一半,取 50 mL 整數並限制在 100–200 mL。
  static int suggestedMl(Resident r, DateTime now) {
    final half = (lagMl(r, now) / 2 / 50).round() * 50;
    return half.clamp(100, 200).toInt();
  }
}
