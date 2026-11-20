import 'dart:async';

import 'package:island_editor/src/render/selection/selectable.dart';
import 'package:flutter/material.dart';

class Cursor extends StatefulWidget {
  const Cursor({
    super.key,
    required this.rect,
    required this.color,
    this.blinkingInterval = 0.5,
    this.shouldBlink = true,
    this.cursorStyle = CursorStyle.verticalLine,
  });

  final double blinkingInterval; // milliseconds
  final bool shouldBlink;
  final CursorStyle cursorStyle;
  final Color color;
  final Rect rect;

  @override
  State<Cursor> createState() => CursorState();
}

class CursorState extends State<Cursor> with SingleTickerProviderStateMixin {
  bool showCursor = true;
  late Timer timer;
  late final AnimationController _blinkController;
  late final Animation<double> _blinkOpacity;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      value: 1.0,
    );
    _blinkOpacity = CurvedAnimation(
      parent: _blinkController,
      curve: Curves.easeInOut,
    );
    timer = _initTimer();
  }

  @override
  void didUpdateWidget(covariant Cursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.shouldBlink && _blinkController.value != 1.0) {
      showCursor = true;
      _blinkController.value = 1.0;
    }
  }

  @override
  void dispose() {
    timer.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  Timer _initTimer() {
    return Timer.periodic(
      Duration(milliseconds: (widget.blinkingInterval * 1000).toInt()),
      (timer) {
        if (!mounted || !widget.shouldBlink) return;
        showCursor = !showCursor;
        if (showCursor) {
          _blinkController.forward();
        } else {
          _blinkController.reverse();
        }
      },
    );
  }

  /// force the cursor widget to show for a while
  void show() {
    showCursor = true;
    _blinkController.value = 1.0;
    timer.cancel();
    timer = _initTimer();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned.fromRect(
      rect: widget.rect,
      duration: const Duration(milliseconds: 65),
      curve: Curves.easeOutCubic,
      child: RepaintBoundary(
        child: IgnorePointer(
          child: FadeTransition(
            opacity: widget.shouldBlink
                ? _blinkOpacity
                : const AlwaysStoppedAnimation<double>(1.0),
            child: _buildCursor(context),
          ),
        ),
      ),
    );
  }

  Widget _buildCursor(BuildContext context) {
    final color = widget.color;
    switch (widget.cursorStyle) {
      case CursorStyle.verticalLine:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      case CursorStyle.borderLine:
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
          ),
        );
      case CursorStyle.cover:
        final size = widget.rect.size;
        return Container(
          width: size.width,
          height: size.height,
          color: color.withValues(alpha: 0.2),
        );
    }
  }
}
