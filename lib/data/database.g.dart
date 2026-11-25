// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CupsTable extends Cups with TableInfo<$CupsTable, CupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capacityMlMeta = const VerificationMeta(
    'capacityMl',
  );
  @override
  late final GeneratedColumn<int> capacityMl = GeneratedColumn<int>(
    'capacity_ml',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(350),
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bleAddressMeta = const VerificationMeta(
    'bleAddress',
  );
  @override
  late final GeneratedColumn<String> bleAddress = GeneratedColumn<String>(
    'ble_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    capacityMl,
    createdAtMs,
    updatedAtMs,
    bleAddress,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cups';
  @override
  VerificationContext validateIntegrity(
    Insertable<CupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('capacity_ml')) {
      context.handle(
        _capacityMlMeta,
        capacityMl.isAcceptableOrUnknown(data['capacity_ml']!, _capacityMlMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('ble_address')) {
      context.handle(
        _bleAddressMeta,
        bleAddress.isAcceptableOrUnknown(data['ble_address']!, _bleAddressMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      capacityMl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capacity_ml'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      bleAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ble_address'],
      ),
    );
  }

  @override
  $CupsTable createAlias(String alias) {
    return $CupsTable(attachedDatabase, alias);
  }
}

class CupRow extends DataClass implements Insertable<CupRow> {
  /// BLE remoteId。
  final String id;
  final String name;

  /// 滿杯容量(mL),水位比例 × 容量 = 水量。
  final int capacityMl;
  final int createdAtMs;
  final int updatedAtMs;

  /// 水杯自己回報的 BLE 位址(Device Status,韌體 0.4.0 起),例如 `58:E6:C5:12:E0:CE`。
  /// 連結照護系統時當作 `cup_hardware_id`;舊韌體為 null,改用 [id]。
  final String? bleAddress;
  const CupRow({
    required this.id,
    required this.name,
    required this.capacityMl,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.bleAddress,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['capacity_ml'] = Variable<int>(capacityMl);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || bleAddress != null) {
      map['ble_address'] = Variable<String>(bleAddress);
    }
    return map;
  }

  CupsCompanion toCompanion(bool nullToAbsent) {
    return CupsCompanion(
      id: Value(id),
      name: Value(name),
      capacityMl: Value(capacityMl),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
      bleAddress: bleAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(bleAddress),
    );
  }

  factory CupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CupRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      capacityMl: serializer.fromJson<int>(json['capacityMl']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      bleAddress: serializer.fromJson<String?>(json['bleAddress']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'capacityMl': serializer.toJson<int>(capacityMl),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'bleAddress': serializer.toJson<String?>(bleAddress),
    };
  }

  CupRow copyWith({
    String? id,
    String? name,
    int? capacityMl,
    int? createdAtMs,
    int? updatedAtMs,
    Value<String?> bleAddress = const Value.absent(),
  }) => CupRow(
    id: id ?? this.id,
    name: name ?? this.name,
    capacityMl: capacityMl ?? this.capacityMl,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    bleAddress: bleAddress.present ? bleAddress.value : this.bleAddress,
  );
  CupRow copyWithCompanion(CupsCompanion data) {
    return CupRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      capacityMl: data.capacityMl.present
          ? data.capacityMl.value
          : this.capacityMl,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      bleAddress: data.bleAddress.present
          ? data.bleAddress.value
          : this.bleAddress,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CupRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('capacityMl: $capacityMl, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('bleAddress: $bleAddress')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, capacityMl, createdAtMs, updatedAtMs, bleAddress);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.capacityMl == this.capacityMl &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs &&
          other.bleAddress == this.bleAddress);
}

class CupsCompanion extends UpdateCompanion<CupRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> capacityMl;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<String?> bleAddress;
  final Value<int> rowid;
  const CupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.capacityMl = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.bleAddress = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CupsCompanion.insert({
    required String id,
    required String name,
    this.capacityMl = const Value.absent(),
    required int createdAtMs,
    required int updatedAtMs,
    this.bleAddress = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<CupRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? capacityMl,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<String>? bleAddress,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (capacityMl != null) 'capacity_ml': capacityMl,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (bleAddress != null) 'ble_address': bleAddress,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CupsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? capacityMl,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<String?>? bleAddress,
    Value<int>? rowid,
  }) {
    return CupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      capacityMl: capacityMl ?? this.capacityMl,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      bleAddress: bleAddress ?? this.bleAddress,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (capacityMl.present) {
      map['capacity_ml'] = Variable<int>(capacityMl.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (bleAddress.present) {
      map['ble_address'] = Variable<String>(bleAddress.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('capacityMl: $capacityMl, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('bleAddress: $bleAddress, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DrinkersTable extends Drinkers
    with TableInfo<$DrinkersTable, DrinkerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DrinkersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dailyGoalMlMeta = const VerificationMeta(
    'dailyGoalMl',
  );
  @override
  late final GeneratedColumn<int> dailyGoalMl = GeneratedColumn<int>(
    'daily_goal_ml',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1500),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalFromServerMeta = const VerificationMeta(
    'goalFromServer',
  );
  @override
  late final GeneratedColumn<bool> goalFromServer = GeneratedColumn<bool>(
    'goal_from_server',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("goal_from_server" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _serverGoalMlMeta = const VerificationMeta(
    'serverGoalMl',
  );
  @override
  late final GeneratedColumn<int> serverGoalMl = GeneratedColumn<int>(
    'server_goal_ml',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    dailyGoalMl,
    updatedAtMs,
    goalFromServer,
    serverGoalMl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drinkers';
  @override
  VerificationContext validateIntegrity(
    Insertable<DrinkerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('daily_goal_ml')) {
      context.handle(
        _dailyGoalMlMeta,
        dailyGoalMl.isAcceptableOrUnknown(
          data['daily_goal_ml']!,
          _dailyGoalMlMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('goal_from_server')) {
      context.handle(
        _goalFromServerMeta,
        goalFromServer.isAcceptableOrUnknown(
          data['goal_from_server']!,
          _goalFromServerMeta,
        ),
      );
    }
    if (data.containsKey('server_goal_ml')) {
      context.handle(
        _serverGoalMlMeta,
        serverGoalMl.isAcceptableOrUnknown(
          data['server_goal_ml']!,
          _serverGoalMlMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DrinkerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DrinkerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      dailyGoalMl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}daily_goal_ml'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      goalFromServer: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}goal_from_server'],
      )!,
      serverGoalMl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_goal_ml'],
      ),
    );
  }

  @override
  $DrinkersTable createAlias(String alias) {
    return $DrinkersTable(attachedDatabase, alias);
  }
}

class DrinkerRow extends DataClass implements Insertable<DrinkerRow> {
  final String id;
  final String name;

  /// 每日目標(mL)。未連結照護系統時由使用者在「設定」修改;
  /// 已連結且照護系統有設定目標時,會被改成照護系統的值。
  final int dailyGoalMl;
  final int updatedAtMs;

  /// 已連結照護系統:每日目標以 Server 為準([serverGoalMl]),不能在 App 修改。
  final bool goalFromServer;

  /// 照護系統設定的每日目標(mL);[goalFromServer] 為 true 而此欄為 null
  /// 代表「照護系統尚未設定目標」,不可以套用任何預設值。
  final int? serverGoalMl;
  const DrinkerRow({
    required this.id,
    required this.name,
    required this.dailyGoalMl,
    required this.updatedAtMs,
    required this.goalFromServer,
    this.serverGoalMl,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['daily_goal_ml'] = Variable<int>(dailyGoalMl);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    map['goal_from_server'] = Variable<bool>(goalFromServer);
    if (!nullToAbsent || serverGoalMl != null) {
      map['server_goal_ml'] = Variable<int>(serverGoalMl);
    }
    return map;
  }

  DrinkersCompanion toCompanion(bool nullToAbsent) {
    return DrinkersCompanion(
      id: Value(id),
      name: Value(name),
      dailyGoalMl: Value(dailyGoalMl),
      updatedAtMs: Value(updatedAtMs),
      goalFromServer: Value(goalFromServer),
      serverGoalMl: serverGoalMl == null && nullToAbsent
          ? const Value.absent()
          : Value(serverGoalMl),
    );
  }

  factory DrinkerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DrinkerRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      dailyGoalMl: serializer.fromJson<int>(json['dailyGoalMl']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      goalFromServer: serializer.fromJson<bool>(json['goalFromServer']),
      serverGoalMl: serializer.fromJson<int?>(json['serverGoalMl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'dailyGoalMl': serializer.toJson<int>(dailyGoalMl),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'goalFromServer': serializer.toJson<bool>(goalFromServer),
      'serverGoalMl': serializer.toJson<int?>(serverGoalMl),
    };
  }

  DrinkerRow copyWith({
    String? id,
    String? name,
    int? dailyGoalMl,
    int? updatedAtMs,
    bool? goalFromServer,
    Value<int?> serverGoalMl = const Value.absent(),
  }) => DrinkerRow(
    id: id ?? this.id,
    name: name ?? this.name,
    dailyGoalMl: dailyGoalMl ?? this.dailyGoalMl,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    goalFromServer: goalFromServer ?? this.goalFromServer,
    serverGoalMl: serverGoalMl.present ? serverGoalMl.value : this.serverGoalMl,
  );
  DrinkerRow copyWithCompanion(DrinkersCompanion data) {
    return DrinkerRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      dailyGoalMl: data.dailyGoalMl.present
          ? data.dailyGoalMl.value
          : this.dailyGoalMl,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      goalFromServer: data.goalFromServer.present
          ? data.goalFromServer.value
          : this.goalFromServer,
      serverGoalMl: data.serverGoalMl.present
          ? data.serverGoalMl.value
          : this.serverGoalMl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DrinkerRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('dailyGoalMl: $dailyGoalMl, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('goalFromServer: $goalFromServer, ')
          ..write('serverGoalMl: $serverGoalMl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    dailyGoalMl,
    updatedAtMs,
    goalFromServer,
    serverGoalMl,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DrinkerRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.dailyGoalMl == this.dailyGoalMl &&
          other.updatedAtMs == this.updatedAtMs &&
          other.goalFromServer == this.goalFromServer &&
          other.serverGoalMl == this.serverGoalMl);
}

class DrinkersCompanion extends UpdateCompanion<DrinkerRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> dailyGoalMl;
  final Value<int> updatedAtMs;
  final Value<bool> goalFromServer;
  final Value<int?> serverGoalMl;
  final Value<int> rowid;
  const DrinkersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.dailyGoalMl = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.goalFromServer = const Value.absent(),
    this.serverGoalMl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DrinkersCompanion.insert({
    required String id,
    required String name,
    this.dailyGoalMl = const Value.absent(),
    required int updatedAtMs,
    this.goalFromServer = const Value.absent(),
    this.serverGoalMl = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<DrinkerRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? dailyGoalMl,
    Expression<int>? updatedAtMs,
    Expression<bool>? goalFromServer,
    Expression<int>? serverGoalMl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (dailyGoalMl != null) 'daily_goal_ml': dailyGoalMl,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (goalFromServer != null) 'goal_from_server': goalFromServer,
      if (serverGoalMl != null) 'server_goal_ml': serverGoalMl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DrinkersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? dailyGoalMl,
    Value<int>? updatedAtMs,
    Value<bool>? goalFromServer,
    Value<int?>? serverGoalMl,
    Value<int>? rowid,
  }) {
    return DrinkersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      dailyGoalMl: dailyGoalMl ?? this.dailyGoalMl,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      goalFromServer: goalFromServer ?? this.goalFromServer,
      serverGoalMl: serverGoalMl ?? this.serverGoalMl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (dailyGoalMl.present) {
      map['daily_goal_ml'] = Variable<int>(dailyGoalMl.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (goalFromServer.present) {
      map['goal_from_server'] = Variable<bool>(goalFromServer.value);
    }
    if (serverGoalMl.present) {
      map['server_goal_ml'] = Variable<int>(serverGoalMl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DrinkersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('dailyGoalMl: $dailyGoalMl, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('goalFromServer: $goalFromServer, ')
          ..write('serverGoalMl: $serverGoalMl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IntakeEventsTable extends IntakeEvents
    with TableInfo<$IntakeEventsTable, IntakeEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IntakeEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _drinkerIdMeta = const VerificationMeta(
    'drinkerId',
  );
  @override
  late final GeneratedColumn<String> drinkerId = GeneratedColumn<String>(
    'drinker_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES drinkers (id)',
    ),
  );
  static const VerificationMeta _cupIdMeta = const VerificationMeta('cupId');
  @override
  late final GeneratedColumn<String> cupId = GeneratedColumn<String>(
    'cup_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<IntakeKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<IntakeKind>($IntakeEventsTable.$converterkind);
  static const VerificationMeta _mlMeta = const VerificationMeta('ml');
  @override
  late final GeneratedColumn<int> ml = GeneratedColumn<int>(
    'ml',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMsMeta = const VerificationMeta(
    'startedAtMs',
  );
  @override
  late final GeneratedColumn<int> startedAtMs = GeneratedColumn<int>(
    'started_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMsMeta = const VerificationMeta(
    'endedAtMs',
  );
  @override
  late final GeneratedColumn<int> endedAtMs = GeneratedColumn<int>(
    'ended_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tzOffsetMinMeta = const VerificationMeta(
    'tzOffsetMin',
  );
  @override
  late final GeneratedColumn<int> tzOffsetMin = GeneratedColumn<int>(
    'tz_offset_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDayMeta = const VerificationMeta(
    'localDay',
  );
  @override
  late final GeneratedColumn<String> localDay = GeneratedColumn<String>(
    'local_day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _beforeMlMeta = const VerificationMeta(
    'beforeMl',
  );
  @override
  late final GeneratedColumn<int> beforeMl = GeneratedColumn<int>(
    'before_ml',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _afterMlMeta = const VerificationMeta(
    'afterMl',
  );
  @override
  late final GeneratedColumn<int> afterMl = GeneratedColumn<int>(
    'after_ml',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<IntakeSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<IntakeSource>($IntakeEventsTable.$convertersource);
  @override
  late final GeneratedColumnWithTypeConverter<IntakeStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(IntakeStatus.ok.name),
      ).withConverter<IntakeStatus>($IntakeEventsTable.$converterstatus);
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _capacityMlMeta = const VerificationMeta(
    'capacityMl',
  );
  @override
  late final GeneratedColumn<int> capacityMl = GeneratedColumn<int>(
    'capacity_ml',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _levelBeforePctMeta = const VerificationMeta(
    'levelBeforePct',
  );
  @override
  late final GeneratedColumn<double> levelBeforePct = GeneratedColumn<double>(
    'level_before_pct',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _levelAfterPctMeta = const VerificationMeta(
    'levelAfterPct',
  );
  @override
  late final GeneratedColumn<double> levelAfterPct = GeneratedColumn<double>(
    'level_after_pct',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeEstimatedMeta = const VerificationMeta(
    'timeEstimated',
  );
  @override
  late final GeneratedColumn<bool> timeEstimated = GeneratedColumn<bool>(
    'time_estimated',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("time_estimated" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sawDrinkingMeta = const VerificationMeta(
    'sawDrinking',
  );
  @override
  late final GeneratedColumn<bool> sawDrinking = GeneratedColumn<bool>(
    'saw_drinking',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("saw_drinking" IN (0, 1))',
    ),
  );
  static const VerificationMeta _tooLongMeta = const VerificationMeta(
    'tooLong',
  );
  @override
  late final GeneratedColumn<bool> tooLong = GeneratedColumn<bool>(
    'too_long',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("too_long" IN (0, 1))',
    ),
  );
  static const VerificationMeta _fwSeqMeta = const VerificationMeta('fwSeq');
  @override
  late final GeneratedColumn<int> fwSeq = GeneratedColumn<int>(
    'fw_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fwKeyMeta = const VerificationMeta('fwKey');
  @override
  late final GeneratedColumn<String> fwKey = GeneratedColumn<String>(
    'fw_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedAtMsMeta = const VerificationMeta(
    'syncedAtMs',
  );
  @override
  late final GeneratedColumn<int> syncedAtMs = GeneratedColumn<int>(
    'synced_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncErrorMeta = const VerificationMeta(
    'syncError',
  );
  @override
  late final GeneratedColumn<String> syncError = GeneratedColumn<String>(
    'sync_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncExcludedMeta = const VerificationMeta(
    'syncExcluded',
  );
  @override
  late final GeneratedColumn<bool> syncExcluded = GeneratedColumn<bool>(
    'sync_excluded',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_excluded" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    drinkerId,
    cupId,
    kind,
    ml,
    startedAtMs,
    endedAtMs,
    tzOffsetMin,
    localDay,
    beforeMl,
    afterMl,
    source,
    status,
    updatedAtMs,
    capacityMl,
    levelBeforePct,
    levelAfterPct,
    timeEstimated,
    sawDrinking,
    tooLong,
    fwSeq,
    fwKey,
    syncedAtMs,
    syncError,
    syncExcluded,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'intake_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<IntakeEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('drinker_id')) {
      context.handle(
        _drinkerIdMeta,
        drinkerId.isAcceptableOrUnknown(data['drinker_id']!, _drinkerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_drinkerIdMeta);
    }
    if (data.containsKey('cup_id')) {
      context.handle(
        _cupIdMeta,
        cupId.isAcceptableOrUnknown(data['cup_id']!, _cupIdMeta),
      );
    }
    if (data.containsKey('ml')) {
      context.handle(_mlMeta, ml.isAcceptableOrUnknown(data['ml']!, _mlMeta));
    } else if (isInserting) {
      context.missing(_mlMeta);
    }
    if (data.containsKey('started_at_ms')) {
      context.handle(
        _startedAtMsMeta,
        startedAtMs.isAcceptableOrUnknown(
          data['started_at_ms']!,
          _startedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtMsMeta);
    }
    if (data.containsKey('ended_at_ms')) {
      context.handle(
        _endedAtMsMeta,
        endedAtMs.isAcceptableOrUnknown(data['ended_at_ms']!, _endedAtMsMeta),
      );
    }
    if (data.containsKey('tz_offset_min')) {
      context.handle(
        _tzOffsetMinMeta,
        tzOffsetMin.isAcceptableOrUnknown(
          data['tz_offset_min']!,
          _tzOffsetMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tzOffsetMinMeta);
    }
    if (data.containsKey('local_day')) {
      context.handle(
        _localDayMeta,
        localDay.isAcceptableOrUnknown(data['local_day']!, _localDayMeta),
      );
    } else if (isInserting) {
      context.missing(_localDayMeta);
    }
    if (data.containsKey('before_ml')) {
      context.handle(
        _beforeMlMeta,
        beforeMl.isAcceptableOrUnknown(data['before_ml']!, _beforeMlMeta),
      );
    }
    if (data.containsKey('after_ml')) {
      context.handle(
        _afterMlMeta,
        afterMl.isAcceptableOrUnknown(data['after_ml']!, _afterMlMeta),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('capacity_ml')) {
      context.handle(
        _capacityMlMeta,
        capacityMl.isAcceptableOrUnknown(data['capacity_ml']!, _capacityMlMeta),
      );
    }
    if (data.containsKey('level_before_pct')) {
      context.handle(
        _levelBeforePctMeta,
        levelBeforePct.isAcceptableOrUnknown(
          data['level_before_pct']!,
          _levelBeforePctMeta,
        ),
      );
    }
    if (data.containsKey('level_after_pct')) {
      context.handle(
        _levelAfterPctMeta,
        levelAfterPct.isAcceptableOrUnknown(
          data['level_after_pct']!,
          _levelAfterPctMeta,
        ),
      );
    }
    if (data.containsKey('time_estimated')) {
      context.handle(
        _timeEstimatedMeta,
        timeEstimated.isAcceptableOrUnknown(
          data['time_estimated']!,
          _timeEstimatedMeta,
        ),
      );
    }
    if (data.containsKey('saw_drinking')) {
      context.handle(
        _sawDrinkingMeta,
        sawDrinking.isAcceptableOrUnknown(
          data['saw_drinking']!,
          _sawDrinkingMeta,
        ),
      );
    }
    if (data.containsKey('too_long')) {
      context.handle(
        _tooLongMeta,
        tooLong.isAcceptableOrUnknown(data['too_long']!, _tooLongMeta),
      );
    }
    if (data.containsKey('fw_seq')) {
      context.handle(
        _fwSeqMeta,
        fwSeq.isAcceptableOrUnknown(data['fw_seq']!, _fwSeqMeta),
      );
    }
    if (data.containsKey('fw_key')) {
      context.handle(
        _fwKeyMeta,
        fwKey.isAcceptableOrUnknown(data['fw_key']!, _fwKeyMeta),
      );
    }
    if (data.containsKey('synced_at_ms')) {
      context.handle(
        _syncedAtMsMeta,
        syncedAtMs.isAcceptableOrUnknown(
          data['synced_at_ms']!,
          _syncedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('sync_error')) {
      context.handle(
        _syncErrorMeta,
        syncError.isAcceptableOrUnknown(data['sync_error']!, _syncErrorMeta),
      );
    }
    if (data.containsKey('sync_excluded')) {
      context.handle(
        _syncExcludedMeta,
        syncExcluded.isAcceptableOrUnknown(
          data['sync_excluded']!,
          _syncExcludedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {cupId, startedAtMs},
  ];
  @override
  IntakeEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IntakeEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      drinkerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}drinker_id'],
      )!,
      cupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cup_id'],
      ),
      kind: $IntakeEventsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      ml: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ml'],
      )!,
      startedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_ms'],
      )!,
      endedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at_ms'],
      ),
      tzOffsetMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tz_offset_min'],
      )!,
      localDay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_day'],
      )!,
      beforeMl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}before_ml'],
      ),
      afterMl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}after_ml'],
      ),
      source: $IntakeEventsTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      status: $IntakeEventsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      capacityMl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capacity_ml'],
      ),
      levelBeforePct: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}level_before_pct'],
      ),
      levelAfterPct: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}level_after_pct'],
      ),
      timeEstimated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}time_estimated'],
      ),
      sawDrinking: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}saw_drinking'],
      ),
      tooLong: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}too_long'],
      ),
      fwSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fw_seq'],
      ),
      fwKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fw_key'],
      ),
      syncedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at_ms'],
      ),
      syncError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_error'],
      ),
      syncExcluded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_excluded'],
      ),
    );
  }

  @override
  $IntakeEventsTable createAlias(String alias) {
    return $IntakeEventsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<IntakeKind, String, String> $converterkind =
      const EnumNameConverter<IntakeKind>(IntakeKind.values);
  static JsonTypeConverter2<IntakeSource, String, String> $convertersource =
      const EnumNameConverter<IntakeSource>(IntakeSource.values);
  static JsonTypeConverter2<IntakeStatus, String, String> $converterstatus =
      const EnumNameConverter<IntakeStatus>(IntakeStatus.values);
}

class IntakeEvent extends DataClass implements Insertable<IntakeEvent> {
  /// UUID v4;上傳照護系統時就是 `client_event_id`。
  final String id;
  final String drinkerId;

  /// 手動輸入可為 null。
  final String? cupId;
  final IntakeKind kind;
  final int ml;

  /// UTC 毫秒。
  final int startedAtMs;
  final int? endedAtMs;

  /// 事件發生當下的時區偏移(分鐘),換時區後「哪一天」不會跑掉。
  final int tzOffsetMin;

  /// 事件發生當地的日期 yyyy-MM-dd(由 startedAtMs + tzOffsetMin 算出),
  /// 日/週/月統計直接以此分組。
  final String localDay;

  /// 拿起前、放下後的水量(mL),除錯與日後重算用。
  final int? beforeMl;
  final int? afterMl;
  final IntakeSource source;
  final IntakeStatus status;
  final int updatedAtMs;

  /// 事件當下的水杯容量(mL),換算 mL 用的那個值。
  final int? capacityMl;

  /// 事件前/後的水位(%,0–100)。韌體事件是韌體送來的 A/B。
  final double? levelBeforePct;
  final double? levelAfterPct;

  /// 時間為估計:韌體送來的事件沒有可信的時間(`time_unknown`),
  /// [startedAtMs] 是 App 收到的時間。null 視為 false。
  final bool? timeEstimated;

  /// 韌體旗標:過程中出現過「飲用中」姿態、過程超過 10 分鐘。非韌體事件為 null。
  final bool? sawDrinking;
  final bool? tooLong;

  /// 韌體事件的 seq(0..2047)。
  final int? fwSeq;

  /// 韌體事件的去重鍵(seq + 時間戳 + A/B),同一筆重送時相同。
  final String? fwKey;

  /// 上傳照護系統成功的時間(UTC 毫秒);null = 還沒同步(新增或修改過)。
  final int? syncedAtMs;

  /// 照護系統拒收這一版紀錄的原因(例如 INVALID_EVENT);有值 = 不再重送,
  /// 直到紀錄再被修改。
  final String? syncError;

  /// true = 這筆紀錄不上傳照護系統,之後再修改也一樣。連結到新的住民時,本機原有的
  /// 紀錄都會標上(Server 會把收到的事件算在 token 所屬的住民身上,連結之前的紀錄
  /// 不能算到他頭上);從備份檔匯入的紀錄也是。
  final bool? syncExcluded;
  const IntakeEvent({
    required this.id,
    required this.drinkerId,
    this.cupId,
    required this.kind,
    required this.ml,
    required this.startedAtMs,
    this.endedAtMs,
    required this.tzOffsetMin,
    required this.localDay,
    this.beforeMl,
    this.afterMl,
    required this.source,
    required this.status,
    required this.updatedAtMs,
    this.capacityMl,
    this.levelBeforePct,
    this.levelAfterPct,
    this.timeEstimated,
    this.sawDrinking,
    this.tooLong,
    this.fwSeq,
    this.fwKey,
    this.syncedAtMs,
    this.syncError,
    this.syncExcluded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['drinker_id'] = Variable<String>(drinkerId);
    if (!nullToAbsent || cupId != null) {
      map['cup_id'] = Variable<String>(cupId);
    }
    {
      map['kind'] = Variable<String>(
        $IntakeEventsTable.$converterkind.toSql(kind),
      );
    }
    map['ml'] = Variable<int>(ml);
    map['started_at_ms'] = Variable<int>(startedAtMs);
    if (!nullToAbsent || endedAtMs != null) {
      map['ended_at_ms'] = Variable<int>(endedAtMs);
    }
    map['tz_offset_min'] = Variable<int>(tzOffsetMin);
    map['local_day'] = Variable<String>(localDay);
    if (!nullToAbsent || beforeMl != null) {
      map['before_ml'] = Variable<int>(beforeMl);
    }
    if (!nullToAbsent || afterMl != null) {
      map['after_ml'] = Variable<int>(afterMl);
    }
    {
      map['source'] = Variable<String>(
        $IntakeEventsTable.$convertersource.toSql(source),
      );
    }
    {
      map['status'] = Variable<String>(
        $IntakeEventsTable.$converterstatus.toSql(status),
      );
    }
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    if (!nullToAbsent || capacityMl != null) {
      map['capacity_ml'] = Variable<int>(capacityMl);
    }
    if (!nullToAbsent || levelBeforePct != null) {
      map['level_before_pct'] = Variable<double>(levelBeforePct);
    }
    if (!nullToAbsent || levelAfterPct != null) {
      map['level_after_pct'] = Variable<double>(levelAfterPct);
    }
    if (!nullToAbsent || timeEstimated != null) {
      map['time_estimated'] = Variable<bool>(timeEstimated);
    }
    if (!nullToAbsent || sawDrinking != null) {
      map['saw_drinking'] = Variable<bool>(sawDrinking);
    }
    if (!nullToAbsent || tooLong != null) {
      map['too_long'] = Variable<bool>(tooLong);
    }
    if (!nullToAbsent || fwSeq != null) {
      map['fw_seq'] = Variable<int>(fwSeq);
    }
    if (!nullToAbsent || fwKey != null) {
      map['fw_key'] = Variable<String>(fwKey);
    }
    if (!nullToAbsent || syncedAtMs != null) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs);
    }
    if (!nullToAbsent || syncError != null) {
      map['sync_error'] = Variable<String>(syncError);
    }
    if (!nullToAbsent || syncExcluded != null) {
      map['sync_excluded'] = Variable<bool>(syncExcluded);
    }
    return map;
  }

  IntakeEventsCompanion toCompanion(bool nullToAbsent) {
    return IntakeEventsCompanion(
      id: Value(id),
      drinkerId: Value(drinkerId),
      cupId: cupId == null && nullToAbsent
          ? const Value.absent()
          : Value(cupId),
      kind: Value(kind),
      ml: Value(ml),
      startedAtMs: Value(startedAtMs),
      endedAtMs: endedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAtMs),
      tzOffsetMin: Value(tzOffsetMin),
      localDay: Value(localDay),
      beforeMl: beforeMl == null && nullToAbsent
          ? const Value.absent()
          : Value(beforeMl),
      afterMl: afterMl == null && nullToAbsent
          ? const Value.absent()
          : Value(afterMl),
      source: Value(source),
      status: Value(status),
      updatedAtMs: Value(updatedAtMs),
      capacityMl: capacityMl == null && nullToAbsent
          ? const Value.absent()
          : Value(capacityMl),
      levelBeforePct: levelBeforePct == null && nullToAbsent
          ? const Value.absent()
          : Value(levelBeforePct),
      levelAfterPct: levelAfterPct == null && nullToAbsent
          ? const Value.absent()
          : Value(levelAfterPct),
      timeEstimated: timeEstimated == null && nullToAbsent
          ? const Value.absent()
          : Value(timeEstimated),
      sawDrinking: sawDrinking == null && nullToAbsent
          ? const Value.absent()
          : Value(sawDrinking),
      tooLong: tooLong == null && nullToAbsent
          ? const Value.absent()
          : Value(tooLong),
      fwSeq: fwSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(fwSeq),
      fwKey: fwKey == null && nullToAbsent
          ? const Value.absent()
          : Value(fwKey),
      syncedAtMs: syncedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAtMs),
      syncError: syncError == null && nullToAbsent
          ? const Value.absent()
          : Value(syncError),
      syncExcluded: syncExcluded == null && nullToAbsent
          ? const Value.absent()
          : Value(syncExcluded),
    );
  }

  factory IntakeEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IntakeEvent(
      id: serializer.fromJson<String>(json['id']),
      drinkerId: serializer.fromJson<String>(json['drinkerId']),
      cupId: serializer.fromJson<String?>(json['cupId']),
      kind: $IntakeEventsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      ml: serializer.fromJson<int>(json['ml']),
      startedAtMs: serializer.fromJson<int>(json['startedAtMs']),
      endedAtMs: serializer.fromJson<int?>(json['endedAtMs']),
      tzOffsetMin: serializer.fromJson<int>(json['tzOffsetMin']),
      localDay: serializer.fromJson<String>(json['localDay']),
      beforeMl: serializer.fromJson<int?>(json['beforeMl']),
      afterMl: serializer.fromJson<int?>(json['afterMl']),
      source: $IntakeEventsTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      status: $IntakeEventsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      capacityMl: serializer.fromJson<int?>(json['capacityMl']),
      levelBeforePct: serializer.fromJson<double?>(json['levelBeforePct']),
      levelAfterPct: serializer.fromJson<double?>(json['levelAfterPct']),
      timeEstimated: serializer.fromJson<bool?>(json['timeEstimated']),
      sawDrinking: serializer.fromJson<bool?>(json['sawDrinking']),
      tooLong: serializer.fromJson<bool?>(json['tooLong']),
      fwSeq: serializer.fromJson<int?>(json['fwSeq']),
      fwKey: serializer.fromJson<String?>(json['fwKey']),
      syncedAtMs: serializer.fromJson<int?>(json['syncedAtMs']),
      syncError: serializer.fromJson<String?>(json['syncError']),
      syncExcluded: serializer.fromJson<bool?>(json['syncExcluded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'drinkerId': serializer.toJson<String>(drinkerId),
      'cupId': serializer.toJson<String?>(cupId),
      'kind': serializer.toJson<String>(
        $IntakeEventsTable.$converterkind.toJson(kind),
      ),
      'ml': serializer.toJson<int>(ml),
      'startedAtMs': serializer.toJson<int>(startedAtMs),
      'endedAtMs': serializer.toJson<int?>(endedAtMs),
      'tzOffsetMin': serializer.toJson<int>(tzOffsetMin),
      'localDay': serializer.toJson<String>(localDay),
      'beforeMl': serializer.toJson<int?>(beforeMl),
      'afterMl': serializer.toJson<int?>(afterMl),
      'source': serializer.toJson<String>(
        $IntakeEventsTable.$convertersource.toJson(source),
      ),
      'status': serializer.toJson<String>(
        $IntakeEventsTable.$converterstatus.toJson(status),
      ),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'capacityMl': serializer.toJson<int?>(capacityMl),
      'levelBeforePct': serializer.toJson<double?>(levelBeforePct),
      'levelAfterPct': serializer.toJson<double?>(levelAfterPct),
      'timeEstimated': serializer.toJson<bool?>(timeEstimated),
      'sawDrinking': serializer.toJson<bool?>(sawDrinking),
      'tooLong': serializer.toJson<bool?>(tooLong),
      'fwSeq': serializer.toJson<int?>(fwSeq),
      'fwKey': serializer.toJson<String?>(fwKey),
      'syncedAtMs': serializer.toJson<int?>(syncedAtMs),
      'syncError': serializer.toJson<String?>(syncError),
      'syncExcluded': serializer.toJson<bool?>(syncExcluded),
    };
  }

  IntakeEvent copyWith({
    String? id,
    String? drinkerId,
    Value<String?> cupId = const Value.absent(),
    IntakeKind? kind,
    int? ml,
    int? startedAtMs,
    Value<int?> endedAtMs = const Value.absent(),
    int? tzOffsetMin,
    String? localDay,
    Value<int?> beforeMl = const Value.absent(),
    Value<int?> afterMl = const Value.absent(),
    IntakeSource? source,
    IntakeStatus? status,
    int? updatedAtMs,
    Value<int?> capacityMl = const Value.absent(),
    Value<double?> levelBeforePct = const Value.absent(),
    Value<double?> levelAfterPct = const Value.absent(),
    Value<bool?> timeEstimated = const Value.absent(),
    Value<bool?> sawDrinking = const Value.absent(),
    Value<bool?> tooLong = const Value.absent(),
    Value<int?> fwSeq = const Value.absent(),
    Value<String?> fwKey = const Value.absent(),
    Value<int?> syncedAtMs = const Value.absent(),
    Value<String?> syncError = const Value.absent(),
    Value<bool?> syncExcluded = const Value.absent(),
  }) => IntakeEvent(
    id: id ?? this.id,
    drinkerId: drinkerId ?? this.drinkerId,
    cupId: cupId.present ? cupId.value : this.cupId,
    kind: kind ?? this.kind,
    ml: ml ?? this.ml,
    startedAtMs: startedAtMs ?? this.startedAtMs,
    endedAtMs: endedAtMs.present ? endedAtMs.value : this.endedAtMs,
    tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
    localDay: localDay ?? this.localDay,
    beforeMl: beforeMl.present ? beforeMl.value : this.beforeMl,
    afterMl: afterMl.present ? afterMl.value : this.afterMl,
    source: source ?? this.source,
    status: status ?? this.status,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    capacityMl: capacityMl.present ? capacityMl.value : this.capacityMl,
    levelBeforePct: levelBeforePct.present
        ? levelBeforePct.value
        : this.levelBeforePct,
    levelAfterPct: levelAfterPct.present
        ? levelAfterPct.value
        : this.levelAfterPct,
    timeEstimated: timeEstimated.present
        ? timeEstimated.value
        : this.timeEstimated,
    sawDrinking: sawDrinking.present ? sawDrinking.value : this.sawDrinking,
    tooLong: tooLong.present ? tooLong.value : this.tooLong,
    fwSeq: fwSeq.present ? fwSeq.value : this.fwSeq,
    fwKey: fwKey.present ? fwKey.value : this.fwKey,
    syncedAtMs: syncedAtMs.present ? syncedAtMs.value : this.syncedAtMs,
    syncError: syncError.present ? syncError.value : this.syncError,
    syncExcluded: syncExcluded.present ? syncExcluded.value : this.syncExcluded,
  );
  IntakeEvent copyWithCompanion(IntakeEventsCompanion data) {
    return IntakeEvent(
      id: data.id.present ? data.id.value : this.id,
      drinkerId: data.drinkerId.present ? data.drinkerId.value : this.drinkerId,
      cupId: data.cupId.present ? data.cupId.value : this.cupId,
      kind: data.kind.present ? data.kind.value : this.kind,
      ml: data.ml.present ? data.ml.value : this.ml,
      startedAtMs: data.startedAtMs.present
          ? data.startedAtMs.value
          : this.startedAtMs,
      endedAtMs: data.endedAtMs.present ? data.endedAtMs.value : this.endedAtMs,
      tzOffsetMin: data.tzOffsetMin.present
          ? data.tzOffsetMin.value
          : this.tzOffsetMin,
      localDay: data.localDay.present ? data.localDay.value : this.localDay,
      beforeMl: data.beforeMl.present ? data.beforeMl.value : this.beforeMl,
      afterMl: data.afterMl.present ? data.afterMl.value : this.afterMl,
      source: data.source.present ? data.source.value : this.source,
      status: data.status.present ? data.status.value : this.status,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      capacityMl: data.capacityMl.present
          ? data.capacityMl.value
          : this.capacityMl,
      levelBeforePct: data.levelBeforePct.present
          ? data.levelBeforePct.value
          : this.levelBeforePct,
      levelAfterPct: data.levelAfterPct.present
          ? data.levelAfterPct.value
          : this.levelAfterPct,
      timeEstimated: data.timeEstimated.present
          ? data.timeEstimated.value
          : this.timeEstimated,
      sawDrinking: data.sawDrinking.present
          ? data.sawDrinking.value
          : this.sawDrinking,
      tooLong: data.tooLong.present ? data.tooLong.value : this.tooLong,
      fwSeq: data.fwSeq.present ? data.fwSeq.value : this.fwSeq,
      fwKey: data.fwKey.present ? data.fwKey.value : this.fwKey,
      syncedAtMs: data.syncedAtMs.present
          ? data.syncedAtMs.value
          : this.syncedAtMs,
      syncError: data.syncError.present ? data.syncError.value : this.syncError,
      syncExcluded: data.syncExcluded.present
          ? data.syncExcluded.value
          : this.syncExcluded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IntakeEvent(')
          ..write('id: $id, ')
          ..write('drinkerId: $drinkerId, ')
          ..write('cupId: $cupId, ')
          ..write('kind: $kind, ')
          ..write('ml: $ml, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('localDay: $localDay, ')
          ..write('beforeMl: $beforeMl, ')
          ..write('afterMl: $afterMl, ')
          ..write('source: $source, ')
          ..write('status: $status, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('capacityMl: $capacityMl, ')
          ..write('levelBeforePct: $levelBeforePct, ')
          ..write('levelAfterPct: $levelAfterPct, ')
          ..write('timeEstimated: $timeEstimated, ')
          ..write('sawDrinking: $sawDrinking, ')
          ..write('tooLong: $tooLong, ')
          ..write('fwSeq: $fwSeq, ')
          ..write('fwKey: $fwKey, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('syncError: $syncError, ')
          ..write('syncExcluded: $syncExcluded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    drinkerId,
    cupId,
    kind,
    ml,
    startedAtMs,
    endedAtMs,
    tzOffsetMin,
    localDay,
    beforeMl,
    afterMl,
    source,
    status,
    updatedAtMs,
    capacityMl,
    levelBeforePct,
    levelAfterPct,
    timeEstimated,
    sawDrinking,
    tooLong,
    fwSeq,
    fwKey,
    syncedAtMs,
    syncError,
    syncExcluded,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IntakeEvent &&
          other.id == this.id &&
          other.drinkerId == this.drinkerId &&
          other.cupId == this.cupId &&
          other.kind == this.kind &&
          other.ml == this.ml &&
          other.startedAtMs == this.startedAtMs &&
          other.endedAtMs == this.endedAtMs &&
          other.tzOffsetMin == this.tzOffsetMin &&
          other.localDay == this.localDay &&
          other.beforeMl == this.beforeMl &&
          other.afterMl == this.afterMl &&
          other.source == this.source &&
          other.status == this.status &&
          other.updatedAtMs == this.updatedAtMs &&
          other.capacityMl == this.capacityMl &&
          other.levelBeforePct == this.levelBeforePct &&
          other.levelAfterPct == this.levelAfterPct &&
          other.timeEstimated == this.timeEstimated &&
          other.sawDrinking == this.sawDrinking &&
          other.tooLong == this.tooLong &&
          other.fwSeq == this.fwSeq &&
          other.fwKey == this.fwKey &&
          other.syncedAtMs == this.syncedAtMs &&
          other.syncError == this.syncError &&
          other.syncExcluded == this.syncExcluded);
}

class IntakeEventsCompanion extends UpdateCompanion<IntakeEvent> {
  final Value<String> id;
  final Value<String> drinkerId;
  final Value<String?> cupId;
  final Value<IntakeKind> kind;
  final Value<int> ml;
  final Value<int> startedAtMs;
  final Value<int?> endedAtMs;
  final Value<int> tzOffsetMin;
  final Value<String> localDay;
  final Value<int?> beforeMl;
  final Value<int?> afterMl;
  final Value<IntakeSource> source;
  final Value<IntakeStatus> status;
  final Value<int> updatedAtMs;
  final Value<int?> capacityMl;
  final Value<double?> levelBeforePct;
  final Value<double?> levelAfterPct;
  final Value<bool?> timeEstimated;
  final Value<bool?> sawDrinking;
  final Value<bool?> tooLong;
  final Value<int?> fwSeq;
  final Value<String?> fwKey;
  final Value<int?> syncedAtMs;
  final Value<String?> syncError;
  final Value<bool?> syncExcluded;
  final Value<int> rowid;
  const IntakeEventsCompanion({
    this.id = const Value.absent(),
    this.drinkerId = const Value.absent(),
    this.cupId = const Value.absent(),
    this.kind = const Value.absent(),
    this.ml = const Value.absent(),
    this.startedAtMs = const Value.absent(),
    this.endedAtMs = const Value.absent(),
    this.tzOffsetMin = const Value.absent(),
    this.localDay = const Value.absent(),
    this.beforeMl = const Value.absent(),
    this.afterMl = const Value.absent(),
    this.source = const Value.absent(),
    this.status = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.capacityMl = const Value.absent(),
    this.levelBeforePct = const Value.absent(),
    this.levelAfterPct = const Value.absent(),
    this.timeEstimated = const Value.absent(),
    this.sawDrinking = const Value.absent(),
    this.tooLong = const Value.absent(),
    this.fwSeq = const Value.absent(),
    this.fwKey = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.syncError = const Value.absent(),
    this.syncExcluded = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IntakeEventsCompanion.insert({
    required String id,
    required String drinkerId,
    this.cupId = const Value.absent(),
    required IntakeKind kind,
    required int ml,
    required int startedAtMs,
    this.endedAtMs = const Value.absent(),
    required int tzOffsetMin,
    required String localDay,
    this.beforeMl = const Value.absent(),
    this.afterMl = const Value.absent(),
    required IntakeSource source,
    this.status = const Value.absent(),
    required int updatedAtMs,
    this.capacityMl = const Value.absent(),
    this.levelBeforePct = const Value.absent(),
    this.levelAfterPct = const Value.absent(),
    this.timeEstimated = const Value.absent(),
    this.sawDrinking = const Value.absent(),
    this.tooLong = const Value.absent(),
    this.fwSeq = const Value.absent(),
    this.fwKey = const Value.absent(),
    this.syncedAtMs = const Value.absent(),
    this.syncError = const Value.absent(),
    this.syncExcluded = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       drinkerId = Value(drinkerId),
       kind = Value(kind),
       ml = Value(ml),
       startedAtMs = Value(startedAtMs),
       tzOffsetMin = Value(tzOffsetMin),
       localDay = Value(localDay),
       source = Value(source),
       updatedAtMs = Value(updatedAtMs);
  static Insertable<IntakeEvent> custom({
    Expression<String>? id,
    Expression<String>? drinkerId,
    Expression<String>? cupId,
    Expression<String>? kind,
    Expression<int>? ml,
    Expression<int>? startedAtMs,
    Expression<int>? endedAtMs,
    Expression<int>? tzOffsetMin,
    Expression<String>? localDay,
    Expression<int>? beforeMl,
    Expression<int>? afterMl,
    Expression<String>? source,
    Expression<String>? status,
    Expression<int>? updatedAtMs,
    Expression<int>? capacityMl,
    Expression<double>? levelBeforePct,
    Expression<double>? levelAfterPct,
    Expression<bool>? timeEstimated,
    Expression<bool>? sawDrinking,
    Expression<bool>? tooLong,
    Expression<int>? fwSeq,
    Expression<String>? fwKey,
    Expression<int>? syncedAtMs,
    Expression<String>? syncError,
    Expression<bool>? syncExcluded,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (drinkerId != null) 'drinker_id': drinkerId,
      if (cupId != null) 'cup_id': cupId,
      if (kind != null) 'kind': kind,
      if (ml != null) 'ml': ml,
      if (startedAtMs != null) 'started_at_ms': startedAtMs,
      if (endedAtMs != null) 'ended_at_ms': endedAtMs,
      if (tzOffsetMin != null) 'tz_offset_min': tzOffsetMin,
      if (localDay != null) 'local_day': localDay,
      if (beforeMl != null) 'before_ml': beforeMl,
      if (afterMl != null) 'after_ml': afterMl,
      if (source != null) 'source': source,
      if (status != null) 'status': status,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (capacityMl != null) 'capacity_ml': capacityMl,
      if (levelBeforePct != null) 'level_before_pct': levelBeforePct,
      if (levelAfterPct != null) 'level_after_pct': levelAfterPct,
      if (timeEstimated != null) 'time_estimated': timeEstimated,
      if (sawDrinking != null) 'saw_drinking': sawDrinking,
      if (tooLong != null) 'too_long': tooLong,
      if (fwSeq != null) 'fw_seq': fwSeq,
      if (fwKey != null) 'fw_key': fwKey,
      if (syncedAtMs != null) 'synced_at_ms': syncedAtMs,
      if (syncError != null) 'sync_error': syncError,
      if (syncExcluded != null) 'sync_excluded': syncExcluded,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IntakeEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? drinkerId,
    Value<String?>? cupId,
    Value<IntakeKind>? kind,
    Value<int>? ml,
    Value<int>? startedAtMs,
    Value<int?>? endedAtMs,
    Value<int>? tzOffsetMin,
    Value<String>? localDay,
    Value<int?>? beforeMl,
    Value<int?>? afterMl,
    Value<IntakeSource>? source,
    Value<IntakeStatus>? status,
    Value<int>? updatedAtMs,
    Value<int?>? capacityMl,
    Value<double?>? levelBeforePct,
    Value<double?>? levelAfterPct,
    Value<bool?>? timeEstimated,
    Value<bool?>? sawDrinking,
    Value<bool?>? tooLong,
    Value<int?>? fwSeq,
    Value<String?>? fwKey,
    Value<int?>? syncedAtMs,
    Value<String?>? syncError,
    Value<bool?>? syncExcluded,
    Value<int>? rowid,
  }) {
    return IntakeEventsCompanion(
      id: id ?? this.id,
      drinkerId: drinkerId ?? this.drinkerId,
      cupId: cupId ?? this.cupId,
      kind: kind ?? this.kind,
      ml: ml ?? this.ml,
      startedAtMs: startedAtMs ?? this.startedAtMs,
      endedAtMs: endedAtMs ?? this.endedAtMs,
      tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
      localDay: localDay ?? this.localDay,
      beforeMl: beforeMl ?? this.beforeMl,
      afterMl: afterMl ?? this.afterMl,
      source: source ?? this.source,
      status: status ?? this.status,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      capacityMl: capacityMl ?? this.capacityMl,
      levelBeforePct: levelBeforePct ?? this.levelBeforePct,
      levelAfterPct: levelAfterPct ?? this.levelAfterPct,
      timeEstimated: timeEstimated ?? this.timeEstimated,
      sawDrinking: sawDrinking ?? this.sawDrinking,
      tooLong: tooLong ?? this.tooLong,
      fwSeq: fwSeq ?? this.fwSeq,
      fwKey: fwKey ?? this.fwKey,
      syncedAtMs: syncedAtMs ?? this.syncedAtMs,
      syncError: syncError ?? this.syncError,
      syncExcluded: syncExcluded ?? this.syncExcluded,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (drinkerId.present) {
      map['drinker_id'] = Variable<String>(drinkerId.value);
    }
    if (cupId.present) {
      map['cup_id'] = Variable<String>(cupId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $IntakeEventsTable.$converterkind.toSql(kind.value),
      );
    }
    if (ml.present) {
      map['ml'] = Variable<int>(ml.value);
    }
    if (startedAtMs.present) {
      map['started_at_ms'] = Variable<int>(startedAtMs.value);
    }
    if (endedAtMs.present) {
      map['ended_at_ms'] = Variable<int>(endedAtMs.value);
    }
    if (tzOffsetMin.present) {
      map['tz_offset_min'] = Variable<int>(tzOffsetMin.value);
    }
    if (localDay.present) {
      map['local_day'] = Variable<String>(localDay.value);
    }
    if (beforeMl.present) {
      map['before_ml'] = Variable<int>(beforeMl.value);
    }
    if (afterMl.present) {
      map['after_ml'] = Variable<int>(afterMl.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $IntakeEventsTable.$convertersource.toSql(source.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $IntakeEventsTable.$converterstatus.toSql(status.value),
      );
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (capacityMl.present) {
      map['capacity_ml'] = Variable<int>(capacityMl.value);
    }
    if (levelBeforePct.present) {
      map['level_before_pct'] = Variable<double>(levelBeforePct.value);
    }
    if (levelAfterPct.present) {
      map['level_after_pct'] = Variable<double>(levelAfterPct.value);
    }
    if (timeEstimated.present) {
      map['time_estimated'] = Variable<bool>(timeEstimated.value);
    }
    if (sawDrinking.present) {
      map['saw_drinking'] = Variable<bool>(sawDrinking.value);
    }
    if (tooLong.present) {
      map['too_long'] = Variable<bool>(tooLong.value);
    }
    if (fwSeq.present) {
      map['fw_seq'] = Variable<int>(fwSeq.value);
    }
    if (fwKey.present) {
      map['fw_key'] = Variable<String>(fwKey.value);
    }
    if (syncedAtMs.present) {
      map['synced_at_ms'] = Variable<int>(syncedAtMs.value);
    }
    if (syncError.present) {
      map['sync_error'] = Variable<String>(syncError.value);
    }
    if (syncExcluded.present) {
      map['sync_excluded'] = Variable<bool>(syncExcluded.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IntakeEventsCompanion(')
          ..write('id: $id, ')
          ..write('drinkerId: $drinkerId, ')
          ..write('cupId: $cupId, ')
          ..write('kind: $kind, ')
          ..write('ml: $ml, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('localDay: $localDay, ')
          ..write('beforeMl: $beforeMl, ')
          ..write('afterMl: $afterMl, ')
          ..write('source: $source, ')
          ..write('status: $status, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('capacityMl: $capacityMl, ')
          ..write('levelBeforePct: $levelBeforePct, ')
          ..write('levelAfterPct: $levelAfterPct, ')
          ..write('timeEstimated: $timeEstimated, ')
          ..write('sawDrinking: $sawDrinking, ')
          ..write('tooLong: $tooLong, ')
          ..write('fwSeq: $fwSeq, ')
          ..write('fwKey: $fwKey, ')
          ..write('syncedAtMs: $syncedAtMs, ')
          ..write('syncError: $syncError, ')
          ..write('syncExcluded: $syncExcluded, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CupsTable cups = $CupsTable(this);
  late final $DrinkersTable drinkers = $DrinkersTable(this);
  late final $IntakeEventsTable intakeEvents = $IntakeEventsTable(this);
  late final Index idxIntakeDay = Index(
    'idx_intake_day',
    'CREATE INDEX idx_intake_day ON intake_events (drinker_id, local_day)',
  );
  late final Index idxIntakeTime = Index(
    'idx_intake_time',
    'CREATE INDEX idx_intake_time ON intake_events (drinker_id, started_at_ms)',
  );
  late final Index idxIntakeFw = Index(
    'idx_intake_fw',
    'CREATE UNIQUE INDEX idx_intake_fw ON intake_events (cup_id, fw_key)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cups,
    drinkers,
    intakeEvents,
    idxIntakeDay,
    idxIntakeTime,
    idxIntakeFw,
  ];
}

typedef $$CupsTableCreateCompanionBuilder = CupsCompanion Function({
  required String id,
  required String name,
  Value<int> capacityMl,
  required int createdAtMs,
  required int updatedAtMs,
  Value<String?> bleAddress,
  Value<int> rowid,
});
typedef $$CupsTableUpdateCompanionBuilder = CupsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> capacityMl,
  Value<int> createdAtMs,
  Value<int> updatedAtMs,
  Value<String?> bleAddress,
  Value<int> rowid,
});

class $$CupsTableFilterComposer extends Composer<_$AppDatabase, $CupsTable> {
  $$CupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get capacityMl => $composableBuilder(
    column: $table.capacityMl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bleAddress => $composableBuilder(
    column: $table.bleAddress,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CupsTableOrderingComposer extends Composer<_$AppDatabase, $CupsTable> {
  $$CupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get capacityMl => $composableBuilder(
    column: $table.capacityMl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bleAddress => $composableBuilder(
    column: $table.bleAddress,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CupsTable> {
  $$CupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get capacityMl => $composableBuilder(
    column: $table.capacityMl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bleAddress => $composableBuilder(
    column: $table.bleAddress,
    builder: (column) => column,
  );
}

class $$CupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CupsTable,
          CupRow,
          $$CupsTableFilterComposer,
          $$CupsTableOrderingComposer,
          $$CupsTableAnnotationComposer,
          $$CupsTableCreateCompanionBuilder,
          $$CupsTableUpdateCompanionBuilder,
          (CupRow, BaseReferences<_$AppDatabase, $CupsTable, CupRow>),
          CupRow,
          PrefetchHooks Function()
        > {
  $$CupsTableTableManager(_$AppDatabase db, $CupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> capacityMl = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<String?> bleAddress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CupsCompanion(
                id: id,
                name: name,
                capacityMl: capacityMl,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                bleAddress: bleAddress,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> capacityMl = const Value.absent(),
                required int createdAtMs,
                required int updatedAtMs,
                Value<String?> bleAddress = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CupsCompanion.insert(
                id: id,
                name: name,
                capacityMl: capacityMl,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                bleAddress: bleAddress,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CupsTable, CupRow>(table),
                  BaseReferences<_$AppDatabase, $CupsTable, CupRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CupsTable,
      CupRow,
      $$CupsTableFilterComposer,
      $$CupsTableOrderingComposer,
      $$CupsTableAnnotationComposer,
      $$CupsTableCreateCompanionBuilder,
      $$CupsTableUpdateCompanionBuilder,
      (CupRow, BaseReferences<_$AppDatabase, $CupsTable, CupRow>),
      CupRow,
      PrefetchHooks Function()
    >;
typedef $$DrinkersTableCreateCompanionBuilder = DrinkersCompanion Function({
  required String id,
  required String name,
  Value<int> dailyGoalMl,
  required int updatedAtMs,
  Value<bool> goalFromServer,
  Value<int?> serverGoalMl,
  Value<int> rowid,
});
typedef $$DrinkersTableUpdateCompanionBuilder = DrinkersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> dailyGoalMl,
  Value<int> updatedAtMs,
  Value<bool> goalFromServer,
  Value<int?> serverGoalMl,
  Value<int> rowid,
});

final class $$DrinkersTableReferences
    extends BaseReferences<_$AppDatabase, $DrinkersTable, DrinkerRow> {
  $$DrinkersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$IntakeEventsTable, List<IntakeEvent>>
  _intakeEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.intakeEvents,
    aliasName: 'drinkers__id__intake_events__drinker_id',
  );

  $$IntakeEventsTableProcessedTableManager get intakeEventsRefs {
    final manager = $$IntakeEventsTableTableManager(
      $_db,
      $_db.intakeEvents,
    ).filter((f) => f.drinkerId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_intakeEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DrinkersTableFilterComposer
    extends Composer<_$AppDatabase, $DrinkersTable> {
  $$DrinkersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dailyGoalMl => $composableBuilder(
    column: $table.dailyGoalMl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get goalFromServer => $composableBuilder(
    column: $table.goalFromServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverGoalMl => $composableBuilder(
    column: $table.serverGoalMl,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> intakeEventsRefs(
    Expression<bool> Function($$IntakeEventsTableFilterComposer f) f,
  ) {
    final $$IntakeEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.intakeEvents,
      getReferencedColumn: (t) => t.drinkerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IntakeEventsTableFilterComposer(
            $db: $db,
            $table: $db.intakeEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DrinkersTableOrderingComposer
    extends Composer<_$AppDatabase, $DrinkersTable> {
  $$DrinkersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dailyGoalMl => $composableBuilder(
    column: $table.dailyGoalMl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get goalFromServer => $composableBuilder(
    column: $table.goalFromServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverGoalMl => $composableBuilder(
    column: $table.serverGoalMl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DrinkersTableAnnotationComposer
    extends Composer<_$AppDatabase, $DrinkersTable> {
  $$DrinkersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get dailyGoalMl => $composableBuilder(
    column: $table.dailyGoalMl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get goalFromServer => $composableBuilder(
    column: $table.goalFromServer,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverGoalMl => $composableBuilder(
    column: $table.serverGoalMl,
    builder: (column) => column,
  );

  Expression<T> intakeEventsRefs<T extends Object>(
    Expression<T> Function($$IntakeEventsTableAnnotationComposer a) f,
  ) {
    final $$IntakeEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.intakeEvents,
      getReferencedColumn: (t) => t.drinkerId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IntakeEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.intakeEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DrinkersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DrinkersTable,
          DrinkerRow,
          $$DrinkersTableFilterComposer,
          $$DrinkersTableOrderingComposer,
          $$DrinkersTableAnnotationComposer,
          $$DrinkersTableCreateCompanionBuilder,
          $$DrinkersTableUpdateCompanionBuilder,
          (DrinkerRow, $$DrinkersTableReferences),
          DrinkerRow,
          PrefetchHooks Function({bool intakeEventsRefs})
        > {
  $$DrinkersTableTableManager(_$AppDatabase db, $DrinkersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DrinkersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DrinkersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DrinkersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> dailyGoalMl = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<bool> goalFromServer = const Value.absent(),
                Value<int?> serverGoalMl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DrinkersCompanion(
                id: id,
                name: name,
                dailyGoalMl: dailyGoalMl,
                updatedAtMs: updatedAtMs,
                goalFromServer: goalFromServer,
                serverGoalMl: serverGoalMl,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> dailyGoalMl = const Value.absent(),
                required int updatedAtMs,
                Value<bool> goalFromServer = const Value.absent(),
                Value<int?> serverGoalMl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DrinkersCompanion.insert(
                id: id,
                name: name,
                dailyGoalMl: dailyGoalMl,
                updatedAtMs: updatedAtMs,
                goalFromServer: goalFromServer,
                serverGoalMl: serverGoalMl,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DrinkersTable, DrinkerRow>(table),
                  $$DrinkersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({intakeEventsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (intakeEventsRefs) db.intakeEvents],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (intakeEventsRefs)
                    await $_getPrefetchedDataByColumns<
                      DrinkerRow,
                      $DrinkersTable,
                      IntakeEvent,
                      $IntakeEventsTable
                    >(
                      currentTable: table,
                      referencedTable: $$DrinkersTableReferences
                          ._intakeEventsRefsTable(db),
                      managerFromTypedResult: (p0) => $$DrinkersTableReferences(
                        db,
                        table,
                        p0,
                      ).intakeEventsRefs,
                      currentColumn: 'id',
                      referencedColumn: 'drinker_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DrinkersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DrinkersTable,
      DrinkerRow,
      $$DrinkersTableFilterComposer,
      $$DrinkersTableOrderingComposer,
      $$DrinkersTableAnnotationComposer,
      $$DrinkersTableCreateCompanionBuilder,
      $$DrinkersTableUpdateCompanionBuilder,
      (DrinkerRow, $$DrinkersTableReferences),
      DrinkerRow,
      PrefetchHooks Function({bool intakeEventsRefs})
    >;
typedef $$IntakeEventsTableCreateCompanionBuilder =
    IntakeEventsCompanion Function({
      required String id,
      required String drinkerId,
      Value<String?> cupId,
      required IntakeKind kind,
      required int ml,
      required int startedAtMs,
      Value<int?> endedAtMs,
      required int tzOffsetMin,
      required String localDay,
      Value<int?> beforeMl,
      Value<int?> afterMl,
      required IntakeSource source,
      Value<IntakeStatus> status,
      required int updatedAtMs,
      Value<int?> capacityMl,
      Value<double?> levelBeforePct,
      Value<double?> levelAfterPct,
      Value<bool?> timeEstimated,
      Value<bool?> sawDrinking,
      Value<bool?> tooLong,
      Value<int?> fwSeq,
      Value<String?> fwKey,
      Value<int?> syncedAtMs,
      Value<String?> syncError,
      Value<bool?> syncExcluded,
      Value<int> rowid,
    });
typedef $$IntakeEventsTableUpdateCompanionBuilder =
    IntakeEventsCompanion Function({
      Value<String> id,
      Value<String> drinkerId,
      Value<String?> cupId,
      Value<IntakeKind> kind,
      Value<int> ml,
      Value<int> startedAtMs,
      Value<int?> endedAtMs,
      Value<int> tzOffsetMin,
      Value<String> localDay,
      Value<int?> beforeMl,
      Value<int?> afterMl,
      Value<IntakeSource> source,
      Value<IntakeStatus> status,
      Value<int> updatedAtMs,
      Value<int?> capacityMl,
      Value<double?> levelBeforePct,
      Value<double?> levelAfterPct,
      Value<bool?> timeEstimated,
      Value<bool?> sawDrinking,
      Value<bool?> tooLong,
      Value<int?> fwSeq,
      Value<String?> fwKey,
      Value<int?> syncedAtMs,
      Value<String?> syncError,
      Value<bool?> syncExcluded,
      Value<int> rowid,
    });

final class $$IntakeEventsTableReferences
    extends BaseReferences<_$AppDatabase, $IntakeEventsTable, IntakeEvent> {
  $$IntakeEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DrinkersTable _drinkerIdTable(_$AppDatabase db) =>
      db.drinkers.createAlias('intake_events__drinker_id__drinkers__id');

  $$DrinkersTableProcessedTableManager get drinkerId {
    final $_column = $_itemColumn<String>('drinker_id')!;

    final manager = $$DrinkersTableTableManager(
      $_db,
      $_db.drinkers,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_drinkerIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$IntakeEventsTableFilterComposer
    extends Composer<_$AppDatabase, $IntakeEventsTable> {
  $$IntakeEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cupId => $composableBuilder(
    column: $table.cupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<IntakeKind, IntakeKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get ml => $composableBuilder(
    column: $table.ml,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAtMs => $composableBuilder(
    column: $table.endedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDay => $composableBuilder(
    column: $table.localDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get beforeMl => $composableBuilder(
    column: $table.beforeMl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get afterMl => $composableBuilder(
    column: $table.afterMl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<IntakeSource, IntakeSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<IntakeStatus, IntakeStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get capacityMl => $composableBuilder(
    column: $table.capacityMl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get levelBeforePct => $composableBuilder(
    column: $table.levelBeforePct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get levelAfterPct => $composableBuilder(
    column: $table.levelAfterPct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get timeEstimated => $composableBuilder(
    column: $table.timeEstimated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sawDrinking => $composableBuilder(
    column: $table.sawDrinking,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tooLong => $composableBuilder(
    column: $table.tooLong,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fwSeq => $composableBuilder(
    column: $table.fwSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fwKey => $composableBuilder(
    column: $table.fwKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get syncExcluded => $composableBuilder(
    column: $table.syncExcluded,
    builder: (column) => ColumnFilters(column),
  );

  $$DrinkersTableFilterComposer get drinkerId {
    final $$DrinkersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.drinkerId,
      referencedTable: $db.drinkers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DrinkersTableFilterComposer(
            $db: $db,
            $table: $db.drinkers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IntakeEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $IntakeEventsTable> {
  $$IntakeEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cupId => $composableBuilder(
    column: $table.cupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ml => $composableBuilder(
    column: $table.ml,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAtMs => $composableBuilder(
    column: $table.endedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDay => $composableBuilder(
    column: $table.localDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get beforeMl => $composableBuilder(
    column: $table.beforeMl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get afterMl => $composableBuilder(
    column: $table.afterMl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get capacityMl => $composableBuilder(
    column: $table.capacityMl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get levelBeforePct => $composableBuilder(
    column: $table.levelBeforePct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get levelAfterPct => $composableBuilder(
    column: $table.levelAfterPct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get timeEstimated => $composableBuilder(
    column: $table.timeEstimated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sawDrinking => $composableBuilder(
    column: $table.sawDrinking,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tooLong => $composableBuilder(
    column: $table.tooLong,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fwSeq => $composableBuilder(
    column: $table.fwSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fwKey => $composableBuilder(
    column: $table.fwKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncError => $composableBuilder(
    column: $table.syncError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get syncExcluded => $composableBuilder(
    column: $table.syncExcluded,
    builder: (column) => ColumnOrderings(column),
  );

  $$DrinkersTableOrderingComposer get drinkerId {
    final $$DrinkersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.drinkerId,
      referencedTable: $db.drinkers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DrinkersTableOrderingComposer(
            $db: $db,
            $table: $db.drinkers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IntakeEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IntakeEventsTable> {
  $$IntakeEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cupId =>
      $composableBuilder(column: $table.cupId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<IntakeKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get ml =>
      $composableBuilder(column: $table.ml, builder: (column) => column);

  GeneratedColumn<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endedAtMs =>
      $composableBuilder(column: $table.endedAtMs, builder: (column) => column);

  GeneratedColumn<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localDay =>
      $composableBuilder(column: $table.localDay, builder: (column) => column);

  GeneratedColumn<int> get beforeMl =>
      $composableBuilder(column: $table.beforeMl, builder: (column) => column);

  GeneratedColumn<int> get afterMl =>
      $composableBuilder(column: $table.afterMl, builder: (column) => column);

  GeneratedColumnWithTypeConverter<IntakeSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumnWithTypeConverter<IntakeStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get capacityMl => $composableBuilder(
    column: $table.capacityMl,
    builder: (column) => column,
  );

  GeneratedColumn<double> get levelBeforePct => $composableBuilder(
    column: $table.levelBeforePct,
    builder: (column) => column,
  );

  GeneratedColumn<double> get levelAfterPct => $composableBuilder(
    column: $table.levelAfterPct,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get timeEstimated => $composableBuilder(
    column: $table.timeEstimated,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get sawDrinking => $composableBuilder(
    column: $table.sawDrinking,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get tooLong =>
      $composableBuilder(column: $table.tooLong, builder: (column) => column);

  GeneratedColumn<int> get fwSeq =>
      $composableBuilder(column: $table.fwSeq, builder: (column) => column);

  GeneratedColumn<String> get fwKey =>
      $composableBuilder(column: $table.fwKey, builder: (column) => column);

  GeneratedColumn<int> get syncedAtMs => $composableBuilder(
    column: $table.syncedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncError =>
      $composableBuilder(column: $table.syncError, builder: (column) => column);

  GeneratedColumn<bool> get syncExcluded => $composableBuilder(
    column: $table.syncExcluded,
    builder: (column) => column,
  );

  $$DrinkersTableAnnotationComposer get drinkerId {
    final $$DrinkersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.drinkerId,
      referencedTable: $db.drinkers,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DrinkersTableAnnotationComposer(
            $db: $db,
            $table: $db.drinkers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IntakeEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IntakeEventsTable,
          IntakeEvent,
          $$IntakeEventsTableFilterComposer,
          $$IntakeEventsTableOrderingComposer,
          $$IntakeEventsTableAnnotationComposer,
          $$IntakeEventsTableCreateCompanionBuilder,
          $$IntakeEventsTableUpdateCompanionBuilder,
          (IntakeEvent, $$IntakeEventsTableReferences),
          IntakeEvent,
          PrefetchHooks Function({bool drinkerId})
        > {
  $$IntakeEventsTableTableManager(_$AppDatabase db, $IntakeEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IntakeEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IntakeEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IntakeEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> drinkerId = const Value.absent(),
                Value<String?> cupId = const Value.absent(),
                Value<IntakeKind> kind = const Value.absent(),
                Value<int> ml = const Value.absent(),
                Value<int> startedAtMs = const Value.absent(),
                Value<int?> endedAtMs = const Value.absent(),
                Value<int> tzOffsetMin = const Value.absent(),
                Value<String> localDay = const Value.absent(),
                Value<int?> beforeMl = const Value.absent(),
                Value<int?> afterMl = const Value.absent(),
                Value<IntakeSource> source = const Value.absent(),
                Value<IntakeStatus> status = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<int?> capacityMl = const Value.absent(),
                Value<double?> levelBeforePct = const Value.absent(),
                Value<double?> levelAfterPct = const Value.absent(),
                Value<bool?> timeEstimated = const Value.absent(),
                Value<bool?> sawDrinking = const Value.absent(),
                Value<bool?> tooLong = const Value.absent(),
                Value<int?> fwSeq = const Value.absent(),
                Value<String?> fwKey = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                Value<bool?> syncExcluded = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntakeEventsCompanion(
                id: id,
                drinkerId: drinkerId,
                cupId: cupId,
                kind: kind,
                ml: ml,
                startedAtMs: startedAtMs,
                endedAtMs: endedAtMs,
                tzOffsetMin: tzOffsetMin,
                localDay: localDay,
                beforeMl: beforeMl,
                afterMl: afterMl,
                source: source,
                status: status,
                updatedAtMs: updatedAtMs,
                capacityMl: capacityMl,
                levelBeforePct: levelBeforePct,
                levelAfterPct: levelAfterPct,
                timeEstimated: timeEstimated,
                sawDrinking: sawDrinking,
                tooLong: tooLong,
                fwSeq: fwSeq,
                fwKey: fwKey,
                syncedAtMs: syncedAtMs,
                syncError: syncError,
                syncExcluded: syncExcluded,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String drinkerId,
                Value<String?> cupId = const Value.absent(),
                required IntakeKind kind,
                required int ml,
                required int startedAtMs,
                Value<int?> endedAtMs = const Value.absent(),
                required int tzOffsetMin,
                required String localDay,
                Value<int?> beforeMl = const Value.absent(),
                Value<int?> afterMl = const Value.absent(),
                required IntakeSource source,
                Value<IntakeStatus> status = const Value.absent(),
                required int updatedAtMs,
                Value<int?> capacityMl = const Value.absent(),
                Value<double?> levelBeforePct = const Value.absent(),
                Value<double?> levelAfterPct = const Value.absent(),
                Value<bool?> timeEstimated = const Value.absent(),
                Value<bool?> sawDrinking = const Value.absent(),
                Value<bool?> tooLong = const Value.absent(),
                Value<int?> fwSeq = const Value.absent(),
                Value<String?> fwKey = const Value.absent(),
                Value<int?> syncedAtMs = const Value.absent(),
                Value<String?> syncError = const Value.absent(),
                Value<bool?> syncExcluded = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IntakeEventsCompanion.insert(
                id: id,
                drinkerId: drinkerId,
                cupId: cupId,
                kind: kind,
                ml: ml,
                startedAtMs: startedAtMs,
                endedAtMs: endedAtMs,
                tzOffsetMin: tzOffsetMin,
                localDay: localDay,
                beforeMl: beforeMl,
                afterMl: afterMl,
                source: source,
                status: status,
                updatedAtMs: updatedAtMs,
                capacityMl: capacityMl,
                levelBeforePct: levelBeforePct,
                levelAfterPct: levelAfterPct,
                timeEstimated: timeEstimated,
                sawDrinking: sawDrinking,
                tooLong: tooLong,
                fwSeq: fwSeq,
                fwKey: fwKey,
                syncedAtMs: syncedAtMs,
                syncError: syncError,
                syncExcluded: syncExcluded,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IntakeEventsTable, IntakeEvent>(table),
                  $$IntakeEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({drinkerId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (drinkerId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.drinkerId,
                        referencedTable: $$IntakeEventsTableReferences
                            ._drinkerIdTable(db),
                        referencedColumn: $$IntakeEventsTableReferences
                            ._drinkerIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$IntakeEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IntakeEventsTable,
      IntakeEvent,
      $$IntakeEventsTableFilterComposer,
      $$IntakeEventsTableOrderingComposer,
      $$IntakeEventsTableAnnotationComposer,
      $$IntakeEventsTableCreateCompanionBuilder,
      $$IntakeEventsTableUpdateCompanionBuilder,
      (IntakeEvent, $$IntakeEventsTableReferences),
      IntakeEvent,
      PrefetchHooks Function({bool drinkerId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CupsTableTableManager get cups => $$CupsTableTableManager(_db, _db.cups);
  $$DrinkersTableTableManager get drinkers =>
      $$DrinkersTableTableManager(_db, _db.drinkers);
  $$IntakeEventsTableTableManager get intakeEvents =>
      $$IntakeEventsTableTableManager(_db, _db.intakeEvents);
}
