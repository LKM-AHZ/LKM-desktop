import 'package:material_ui/material_ui.dart';

/// Whether descendant glass surfaces render the liquid-glass shader material
/// or fall back to a flat Material surface.
///
/// Scoped once near the root of an app. Glass costs a backdrop copy plus a
/// shader pass on every frame a surface is on screen; turning this off keeps
/// every layout identical while painting the same capsules with a tonal
/// Material fill instead.
///
/// Defaults to `true` when no [GlassEffects] ancestor is present, so a surface
/// rendered in isolation (a test, a sheet) still gets the glass material.
class GlassEffects extends InheritedWidget {
  final bool enabled;

  const GlassEffects({super.key, required this.enabled, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassEffects>()?.enabled ??
      true;

  @override
  bool updateShouldNotify(GlassEffects oldWidget) =>
      oldWidget.enabled != enabled;
}
