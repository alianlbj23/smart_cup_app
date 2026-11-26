import 'package:flutter/material.dart';

import 'theme.dart';

/// 「正在尋找水杯」的動態圖示:藍牙圖示外圍有一圈一圈往外擴散、淡出的波紋。
///
/// 系統設定關閉動畫(無障礙)時只顯示靜止的圖示。
class SearchingIndicator extends StatefulWidget {
  const SearchingIndicator({super.key, this.size = 28});

  /// 中央圖示的大小;整個 widget 的邊長也是這個值(波紋畫在範圍內)。
  final double size;

  @override
  State<SearchingIndicator> createState() => _SearchingIndicatorState();
}

class _SearchingIndicatorState extends State<SearchingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在尋找水杯',
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _RipplePainter(_controller.value),
            child: child,
          ),
          child: Icon(
            Icons.bluetooth_searching,
            color: AppColors.teal,
            size: widget.size * 0.72,
          ),
        ),
      ),
    );
  }
}

/// 兩圈相差半個週期的波紋,從中央擴散到邊緣並淡出。
class _RipplePainter extends CustomPainter {
  _RipplePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (final offset in const [0.0, 0.5]) {
      final t = (progress + offset) % 1.0;
      canvas.drawCircle(
        center,
        maxRadius * (0.45 + 0.55 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.teal.withValues(alpha: 0.55 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress;
}
