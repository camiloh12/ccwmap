import 'dart:math' as math;
import 'package:flutter/material.dart';

class CompassButton extends StatefulWidget {
  final Listenable? listenable;
  final double Function()? bearingGetter;
  final VoidCallback onReset;

  const CompassButton({
    super.key,
    required this.listenable,
    required this.bearingGetter,
    required this.onReset,
  });

  @override
  State<CompassButton> createState() => _CompassButtonState();
}

class _CompassButtonState extends State<CompassButton> {
  double _bearing = 0.0;

  @override
  void initState() {
    super.initState();
    _readBearing();
    widget.listenable?.addListener(_onChange);
  }

  @override
  void didUpdateWidget(CompassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_onChange);
      widget.listenable?.addListener(_onChange);
      _readBearing();
    }
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_onChange);
    super.dispose();
  }

  void _readBearing() {
    final next = widget.bearingGetter?.call() ?? 0.0;
    _bearing = next;
  }

  void _onChange() {
    final next = widget.bearingGetter?.call() ?? 0.0;
    if (next != _bearing) {
      setState(() => _bearing = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      // Stacked with another FAB on MapScreen; opt out of Hero to avoid
      // "multiple heroes share the same tag" on route push/pop.
      heroTag: null,
      onPressed: widget.onReset,
      backgroundColor: const Color(0xFFE8DEF8),
      elevation: 4,
      tooltip: 'Reset map orientation to north',
      child: Transform.rotate(
        // Icons.explore is drawn with its N-pointer at the NE corner;
        // the extra -45° rotates visual-N to straight up at bearing 0.
        angle: -(_bearing + 45.0) * math.pi / 180.0,
        child: const Icon(
          Icons.explore,
          color: Colors.black87,
          semanticLabel: 'Reset map orientation to north',
        ),
      ),
    );
  }
}
