import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/accounts/screens/progress.dart';

/// Legacy route kept for existing links; the implementation lives in the
/// account progress screen.
@RoutePage()
class PointsScreen extends StatelessWidget {
  const PointsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ProgressScreen();
}
