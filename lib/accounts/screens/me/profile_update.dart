import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island/accounts/screens/me/account_settings.dart';

/// Legacy deep links share the current LKM profile and security settings.
@RoutePage()
class AccountUpdateProfileScreen extends StatelessWidget {
  const AccountUpdateProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const AccountSettingsScreen();
}
