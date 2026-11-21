import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:island/drive/widgets/cloud_files.dart';

/// The desktop shell's compact, shared navigation header.
class WorkbenchHeader extends StatelessWidget {
  const WorkbenchHeader({
    super.key,
    required this.title,
    required this.onSearch,
    required this.onAccount,
    required this.onSettings,
    this.avatarUrl,
    this.fallbackName,
  });

  final String title;
  final String? avatarUrl;
  final String? fallbackName;
  final VoidCallback onSearch;
  final VoidCallback onAccount;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (constraints.maxWidth > 640)
                          TextSpan(
                            text: '${'workbench.community'.tr()}  /  ',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        TextSpan(text: title),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: constraints.maxWidth > 640 ? 280 : 160,
                  child: OutlinedButton.icon(
                    onPressed: onSearch,
                    icon: const Icon(Symbols.search, size: 17),
                    label: Text(
                      'workbench.search'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: colors.onSurfaceVariant,
                      backgroundColor: colors.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'settings'.tr(),
                  onPressed: onSettings,
                  icon: const Icon(Symbols.settings, size: 20),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onAccount,
                  child: avatarUrl != null || fallbackName != null
                      ? ProfilePictureWidget(
                          imageUrl: avatarUrl,
                          fallbackName: fallbackName,
                          radius: 13,
                        )
                      : Text('login'.tr()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class WorkbenchBrand extends StatelessWidget {
  const WorkbenchBrand({super.key, required this.expanded});
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: expanded ? 224 : 80,
      height: 84,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 22),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'LKM',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (expanded) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'workbench.brand'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'LKM COMMUNITY',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        letterSpacing: 1.2,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
