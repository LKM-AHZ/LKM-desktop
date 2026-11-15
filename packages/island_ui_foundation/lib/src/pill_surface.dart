import 'package:island_ui_foundation/src/glass_effects.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

/// Alpha of the pill's shadow once it is fully surfaced.
const double _kPillShadowOpacity = 0.12;

/// Stroke of the ring a loading pill paints along its own edge.
const double _kPillRingStroke = 2.0;

/// Share of the capsule's perimeter the indeterminate ring sweeps.
const double _kPillRingSweep = 0.26;

/// One full lap of the indeterminate ring.
const Duration _kPillRingPeriod = Duration(milliseconds: 1100);

/// How long the loading border takes to fade in or out.
const Duration _kPillRingFade = Duration(milliseconds: 220);

/// Default fully-rounded capsule radius.
const BorderRadius _kDefaultPillRadius = BorderRadius.all(Radius.circular(999));

/// The painted chrome of a floating pill or rounded surface.
///
/// Geometry is fixed: the capsule keeps the same [margin], [radius] and height
/// at every scroll offset, so its controls never move under the user's thumb.
/// Only the surface fades in with [t] (0..1): invisible at rest, liquid glass
/// (or tonal Material surface) over the content beneath once the page moves.
///
/// When [GlassEffects] is on, a [LiquidGlassLayer] samples the page behind
/// the capsule and refracts it through a [LiquidRoundedSuperellipse].
///
/// When [GlassEffects] is off, the capsule is painted as a
/// `colorScheme.surfaceContainer` Material fill with an outer elevation
/// shadow and no border — same geometry, same fade, no backdrop sample or
/// shader pass.
///
/// The surface layer and shadow are skipped while [t] is 0: there is nothing
/// under the bar, and an idle layer would still copy the backdrop.
///
/// A loading pill laps its own outline instead of sitting still: see
/// [loading].
class PillSurface extends StatelessWidget {
  /// Fade position, 0..1. Drives the surface and shadow together.
  final double t;

  /// Outer margin of the capsule, painted against the container it floats in.
  final EdgeInsetsGeometry margin;

  /// Corner radius of the capsule.
  final BorderRadius radius;

  /// Inset of [child] inside the capsule.
  final EdgeInsetsGeometry contentPadding;

  final Widget child;

  /// Draw the capsule's outline as a spinner: an arc laps the edge.
  ///
  /// The ring deliberately ignores [t] so a loader remains legible while the
  /// page is still sitting at its top.
  final bool loading;

  /// Determinate progress (0..1) drawn along the capsule's outline.
  ///
  /// Ignored while [loading] is true. Null or <= 0 paints nothing.
  final double? progress;

  /// Highlight the capsule edge using [ColorScheme.primary] (e.g. drag-over).
  final bool highlight;

  /// Optional brightness override for surfaces pinned over dark/light media.
  final Brightness? brightness;

  const PillSurface({
    super.key,
    this.t = 1.0,
    this.margin = EdgeInsets.zero,
    this.radius = _kDefaultPillRadius,
    this.contentPadding = EdgeInsets.zero,
    required this.child,
    this.loading = false,
    this.progress,
    this.highlight = false,
    this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveBrightness = brightness ?? theme.brightness;
    final glass = GlassEffects.of(context);
    final effectiveT = t.clamp(0.0, 1.0);
    final effectiveProgress = (progress ?? 0.0).clamp(0.0, 1.0);

    return Container(
      margin: margin,
      // The shadow wraps the Stack so it always paints behind the pill surface
      // rather than over `_SolidSurface` / `_GlassLayer`. A plain [DecoratedBox]
      // tracks [t] synchronously without restarting an implicit animation on
      // every scroll frame.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: effectiveT == 0
              ? null
              : [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(
                      alpha: _kPillShadowOpacity * effectiveT,
                    ),
                    blurRadius: 12 * effectiveT,
                    offset: Offset(0, 4 * effectiveT),
                  ),
                ],
        ),
        // `passthrough` so the pill's height comes from its controls: the
        // surface layer is positioned and contributes no size of its own.
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            if (effectiveT > 0)
              Positioned.fill(
                child: glass
                    ? _GlassLayer(
                        t: effectiveT,
                        brightness: effectiveBrightness,
                        radius: radius,
                      )
                    : _SolidSurface(
                        t: effectiveT,
                        colorScheme: colorScheme,
                        radius: radius,
                        highlight: highlight,
                      ),
              ),
            if (effectiveT > 0 && highlight && glass)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: effectiveT),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: contentPadding,
              child: Material(type: MaterialType.transparency, child: child),
            ),
            // The ring keeps a slot while it fades out, so leaving the loading
            // state dissolves the arc instead of clipping it off mid-lap.
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: _kPillRingFade,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: loading
                    ? _PillRing(
                        key: const ValueKey('pill-ring'),
                        radius: radius,
                        color: colorScheme.primary,
                      )
                    : (effectiveProgress > 0
                          ? _PillProgressRing(
                              key: const ValueKey('pill-progress-ring'),
                              radius: radius,
                              color: colorScheme.primary,
                              progress: effectiveProgress,
                            )
                          : const SizedBox.shrink(key: ValueKey('pill-ring-idle'))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassLayer extends StatelessWidget {
  final double t;
  final Brightness brightness;
  final BorderRadius radius;

  const _GlassLayer({
    required this.t,
    required this.brightness,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassLayer(
      settings: LiquidGlassSettings.ios27Regular(brightness: brightness),
      // `defaultAppearance` rather than a per-shape appearance: the pill holds
      // a single shape, and the layer-level appearance is the cheaper shader
      // path.
      defaultAppearance: LiquidGlassAppearance.ios27Regular(
        brightness: brightness,
      ).copyWith(visibility: t),
      // The layer sizes itself from this box; the shape takes the capsule's
      // whole area and paints no content of its own.
      child: LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: radius.topLeft.x),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SolidSurface extends StatelessWidget {
  final double t;
  final ColorScheme colorScheme;
  final BorderRadius radius;
  final bool highlight;

  const _SolidSurface({
    required this.t,
    required this.colorScheme,
    required this.radius,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: t),
        borderRadius: radius,
        border: highlight
            ? Border.all(
                color: colorScheme.primary.withValues(alpha: t),
                width: 1.5,
              )
            : null,
      ),
    );
  }
}

/// The capsule's own edge as a spinner.
class _PillRing extends StatefulWidget {
  final BorderRadius radius;
  final Color color;

  const _PillRing({super.key, required this.radius, required this.color});

  @override
  State<_PillRing> createState() => _PillRingState();
}

class _PillRingState extends State<_PillRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kPillRingPeriod,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        // A childless [CustomPaint] takes its size from its child, and inside
        // the switcher's stack there is none — it would collapse to zero and
        // paint nothing. `SizedBox.expand` gives the painter the bar's box.
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _PillRingPainter(
              radius: widget.radius,
              color: widget.color,
              sweep: _controller,
            ),
          ),
        ),
      ),
    );
  }
}

void _paintPillOutlineArc(
  Canvas canvas,
  Size size, {
  required BorderRadius radius,
  required Color color,
  required double startFraction,
  required double sweepFraction,
}) {
  if (size.isEmpty) return;

  // Inset by half the stroke so the ring's outer edge lands on the capsule
  // outline the glass contour follows, not half a stroke outside it.
  final outline = radius
      .toRRect(Offset.zero & size)
      .deflate(_kPillRingStroke / 2);
  // A capsule is a single contour, so one metric covers the whole edge.
  final metric = (Path()..addRRect(outline)).computeMetrics().first;
  final total = metric.length;
  if (total <= 0) return;

  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _kPillRingStroke
    ..strokeCap = StrokeCap.round
    ..color = color;

  // The rounded rect's contour starts at the middle of its top edge, which
  // is exactly where a lap should begin. This offsets the *extraction*
  // only, never the canvas: rotating the canvas would turn the capsule
  // itself and paint the arc down the page.
  final clampedSweep = sweepFraction.clamp(0.0, 1.0);
  if (clampedSweep <= 0) return;
  if (clampedSweep >= 1.0) {
    canvas.drawRRect(outline, paint);
    return;
  }

  final start = (startFraction * total) % total;
  final extent = total * clampedSweep;

  void draw(double from, double to) {
    if (to - from < 0.5) return;
    canvas.drawPath(
      metric.extractPath(from.clamp(0.0, total), to.clamp(0.0, total)),
      paint,
    );
  }

  if (start + extent <= total) {
    draw(start, start + extent);
  } else {
    // The lap straddles the seam: paint the tail and the head separately.
    draw(start, total);
    draw(0, start + extent - total);
  }
}

class _PillProgressRing extends StatelessWidget {
  final BorderRadius radius;
  final Color color;
  final double progress;

  const _PillProgressRing({
    super.key,
    required this.radius,
    required this.color,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _PillProgressPainter(
              radius: radius,
              color: color,
              progress: progress,
            ),
          ),
        ),
      ),
    );
  }
}

class _PillProgressPainter extends CustomPainter {
  final BorderRadius radius;
  final Color color;
  final double progress;

  _PillProgressPainter({
    required this.radius,
    required this.color,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintPillOutlineArc(
      canvas,
      size,
      radius: radius,
      color: color,
      startFraction: 0.0,
      sweepFraction: progress,
    );
  }

  @override
  bool shouldRepaint(covariant _PillProgressPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.color != color ||
        oldDelegate.progress != progress;
  }
}

class _PillRingPainter extends CustomPainter {
  final BorderRadius radius;
  final Color color;
  final Animation<double> sweep;

  _PillRingPainter({
    required this.radius,
    required this.color,
    required this.sweep,
  }) : super(repaint: sweep);

  @override
  void paint(Canvas canvas, Size size) {
    _paintPillOutlineArc(
      canvas,
      size,
      radius: radius,
      color: color,
      startFraction: sweep.value,
      sweepFraction: _kPillRingSweep,
    );
  }

  @override
  bool shouldRepaint(covariant _PillRingPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.color != color;
  }
}
