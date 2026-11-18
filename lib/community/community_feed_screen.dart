import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/discovery/explore.dart';

/// Legacy community tab route. The merged timeline lives in the explore
/// screen; this keeps old deep links working without a second implementation.
@RoutePage()
class CommunityFeedScreen extends StatelessWidget {
  const CommunityFeedScreen({super.key});

  @override
  Widget build(BuildContext context) => const ExploreScreen();
}
