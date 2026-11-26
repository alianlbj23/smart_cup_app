import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'chart_style.dart';

/// 讓圖表可以沿時間軸(水平)放大、縮小、左右移動。
///
/// - 觸控:雙指張開/捏合縮放,單指拖曳移動。
/// - 滑鼠:滾輪縮放,按住拖曳移動。
/// - 圖表下方的「+」「−」按鈕:以畫面中央為準放大、縮小(和看盤軟體的 K 線圖一樣)。
///
/// [builder] 收到的 config 要交給 fl_chart 圖表的 `transformationConfig`;同一個
/// config 交給多張圖時,它們會一起縮放(日檢視上下兩張圖共用時間軸)。
/// scale 是目前的放大倍率(1 = 沒有放大),可以用來調整座標軸刻度的疏密。
///
/// 放大狀態存在這個 widget 裡:換一天、換範圍時給不同的 key 就會還原。
class ChartZoom extends StatefulWidget {
  const ChartZoom({
    super.key,
    required this.maxScale,
    required this.builder,
    this.leftReserved = ChartStyle.leftReserved,
  });

  /// 最多放大幾倍。
  final double maxScale;

  /// 圖表左邊留給 Y 軸文字的寬度;這一段不屬於可以縮放的範圍。
  final double leftReserved;

  /// 按一次「+」「−」放大、縮小的倍數。
  static const buttonStep = 1.6;

  final Widget Function(
    BuildContext context,
    FlTransformationConfig config,
    double scale,
  ) builder;

  @override
  State<ChartZoom> createState() => _ChartZoomState();
}

class _ChartZoomState extends State<ChartZoom> {
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 以可見範圍的中央為準放大([factor] > 1)或縮小;[viewport] 是繪圖區的寬度。
  void _zoomBy(double factor, double viewport) {
    final matrix = _controller.value;
    final scale = matrix.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, widget.maxScale);
    if ((next - scale).abs() < 1e-6) return;
    final center = viewport / 2;
    // 目前在畫面中央的那一點,放大後仍然留在中央;再限制不要超出圖的左右邊界。
    final sceneX = (center - matrix.getTranslation().x) / scale;
    final translateX =
        (center - next * sceneX).clamp(viewport - next * viewport, 0.0);
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, next)
      ..setEntry(1, 1, next)
      ..setEntry(0, 3, translateX);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final viewport =
          (constraints.maxWidth - widget.leftReserved).clamp(1.0, double.infinity);
      return _build(context, viewport);
    });
  }

  Widget _build(BuildContext context, double viewport) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final scale = _controller.value.getMaxScaleOnAxis();
        final zoomed = scale > 1.001;
        final atMax = scale >= widget.maxScale - 0.001;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.builder(
              context,
              FlTransformationConfig(
                scaleAxis: FlScaleAxis.horizontal,
                minScale: 1,
                maxScale: widget.maxScale,
                transformationController: _controller,
              ),
              zoomed ? scale : 1,
            ),
            // 高度固定:「還原」出現、消失時版面不會跳動。
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '雙指、滾輪或 + − 可以放大',
                      style: mutedSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: zoomed
                        ? () => _zoomBy(1 / ChartZoom.buttonStep, viewport)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: '縮小',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: atMax
                        ? null
                        : () => _zoomBy(ChartZoom.buttonStep, viewport),
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: '放大',
                    visualDensity: VisualDensity.compact,
                  ),
                  if (zoomed)
                    TextButton(
                      onPressed: () => _controller.value = Matrix4.identity(),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('還原'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 0–24 時的時間軸在放大 [scale] 倍時,每幾個小時標一個刻度。
/// 沒放大時每 6 小時一格;放到最大時每半小時一格。
double hourIntervalForScale(double scale) {
  if (scale < 2) return 6;
  if (scale < 4) return 3;
  if (scale < 8) return 2;
  if (scale < 16) return 1;
  return 0.5;
}

/// 時間軸刻度的文字:整點只寫小時(`06`),不是整點寫時分(`14:30`)。
String hourAxisLabel(double hour) {
  final minutes = (hour * 60).round();
  final hh = (minutes ~/ 60).toString().padLeft(2, '0');
  final mm = minutes % 60;
  return mm == 0 ? hh : '$hh:${mm.toString().padLeft(2, '0')}';
}
