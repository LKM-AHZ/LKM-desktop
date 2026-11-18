import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

import 'package:island/accounts/screens/profile.dart';

/// Legacy id-based profile route; the implementation lives in the account
/// profile screen.
@RoutePage()
class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => AccountProfileView(userId: id);
}
