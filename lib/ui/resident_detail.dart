import 'package:flutter/material.dart';

import '../models/resident.dart';
import '../state/care_store.dart';
import '../state/cup_connection_manager.dart';
import 'cup_reading.dart';
import 'cup_link.dart';
import 'theme.dart';

/// 住民頭像(姓氏)。
class ResidentAvatar extends StatelessWidget {
  const ResidentAvatar({super.key, required this.resident, this.radius = 20});

  final Resident resident;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.tealSoft,
      child: Text(
        resident.name.isEmpty ? '?' : resident.name.characters.first,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: AppColors.teal,
        ),
      ),
    );
  }
}

String residentSubtitle(Resident r) => [
      if (r.room.isNotEmpty) r.room,
      if (r.age > 0) '${r.age}歲',
    ].join(' · ');

/// 選取住民的今日飲水量、快速登錄與水杯配對。
class ResidentDetail extends StatelessWidget {
  const ResidentDetail({
    super.key,
    required this.manager,
    required this.store,
    required this.resident,
    required this.now,
  });

  final CupConnectionManager manager;
  final CareStore store;
  final Resident resident;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = resident;
    final total = r.totalOn(now);
    final behind = HydrationSchedule.isBehind(r, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResidentAvatar(resident: r),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(residentSubtitle(r), style: mutedSmall),
                  if (r.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [for (final t in r.tags) _Tag(t)],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('今日已飲用', style: mutedSmall),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fmtMl(total),
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w700, height: 1.1)),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 3),
              child: Text('mL',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            Text('目標 ${fmtMl(r.goalMl)} mL', style: mutedSmall),
          ],
        ),
        const SizedBox(height: 8),
        ProgressBar(
          value: r.progressOn(now),
          color: behind ? AppColors.orange : AppColors.teal,
          height: 8,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final ml in const [100, 150]) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => store.addIntake(r.id, ml),
                  child: Text('+$ml mL'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                onPressed: () => store.addIntake(r.id, 200),
                child: const Text('+200 mL'),
              ),
            ),
          ],
        ),
        if (r.entriesOn(now).lastOrNull case final last?)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => store.undoLastIntake(r.id),
              icon: const Icon(Icons.undo, size: 16),
              label: Text('復原 ${fmtTime(last.time)} 的 ${last.ml} mL'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.muted,
                textStyle: const TextStyle(fontSize: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
          )
        else
          const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        CupCard(manager: manager, store: store, resident: r, now: now),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: mutedSmall.copyWith(fontSize: 11)),
    );
  }
}

/// 住民的水杯配對狀態與操作。
class CupCard extends StatelessWidget {
  const CupCard({
    super.key,
    required this.manager,
    required this.store,
    required this.resident,
    required this.now,
  });

  final CupConnectionManager manager;
  final CareStore store;
  final Resident resident;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = resident;
    final link = cupLinkOf(manager, r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.local_drink, size: 18, color: AppColors.teal),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('配對水杯',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            CupStatusPill(link: link),
          ],
        ),
        const SizedBox(height: 8),
        if (link == CupLink.none) ...[
          const Text('尚未配對水杯,配對後可接收水杯資料。', style: mutedSmall),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => showCupPairingDialog(context, manager, store, r),
            icon: const Icon(Icons.bluetooth_searching, size: 18),
            label: const Text('配對水杯'),
          ),
        ] else ...[
          Text(cupDisplayName(r.cupName),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(r.cupId!, style: mutedSmall),
          if (link == CupLink.connected) _connectedInfo(),
          if (link != CupLink.offline && link != CupLink.connected)
            if (manager.message case final msg?)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(msg,
                    style: const TextStyle(fontSize: 12, color: AppColors.red)),
              ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _primaryAction(link)),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => unpairCup(context, manager, store, r),
                  child: const Text('解除配對'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _connectedInfo() {
    final battery = manager.deviceStatus?.batteryPercent;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.battery_std, size: 15, color: AppColors.muted),
              const SizedBox(width: 2),
              Text(battery == null ? '電量讀取中…' : '電量 $battery%',
                  style: mutedSmall),
              const Spacer(),
              Text('共 ${manager.receivedCount} 筆', style: mutedSmall),
            ],
          ),
          const SizedBox(height: 6),
          // TODO: 將水量變化換算為飲水量自動登錄(規格書 §8)。
          CupReading(manager: manager, now: now),
        ],
      ),
    );
  }

  Widget _primaryAction(CupLink link) => switch (link) {
        CupLink.connected => OutlinedButton(
            onPressed: manager.disconnect,
            child: const Text('中斷連線'),
          ),
        CupLink.linking => OutlinedButton(
            onPressed: manager.disconnect,
            child: const Text('取消連線'),
          ),
        CupLink.notFound => FilledButton(
            onPressed: manager.startAutoReconnect,
            child: const Text('重試'),
          ),
        _ => FilledButton(
            onPressed: () => connectCup(manager, resident),
            child: const Text('連線'),
          ),
      };
}
