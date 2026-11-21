import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:styled_widget/styled_widget.dart';

import 'package:island/accounts/account_pod.dart';
import 'package:island/auth/login_controller.dart';
import 'package:island/auth/oauth_desktop.dart';
import 'package:island/auth/totp_setup_dialog.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/api/users_api.dart';
import 'package:island/drive/widgets/cloud_files.dart';
import 'package:island/core/network.dart';
import 'package:island/core/services/nfc_scan_service.dart';
import 'package:island/core/theme.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';
import 'package:island/shared/widgets/empty_state.dart';
import 'package:island/shared/widgets/layouts/sheet_scaffold.dart';
import 'package:island/shared/widgets/response.dart';

part 'account_settings.g.dart';
part 'account_settings.freezed.dart';

bool get _supportsPhysicalPassportScan =>
    !kIsWeb &&
    (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.operatingSystem == 'ohos');

@riverpod
Future<List<SnAuthFactor>> authFactors(Ref ref) async {
  final client = ref.read(solarNetworkClientProvider);
  return await client.auth.getFactors();
}

@riverpod
Future<List<SnContactMethod>> contactMethods(Ref ref) async {
  final client = ref.read(solarNetworkClientProvider);
  return await client.auth.getContacts();
}

@riverpod
Future<List<SnAccountConnection>> accountConnections(Ref ref) async {
  final client = ref.read(solarNetworkClientProvider);
  return await client.auth.getConnections();
}

@riverpod
Future<SnPublishingSettings> publishingSettings(Ref ref) async {
  final client = ref.read(solarNetworkClientProvider);
  return await client.sphere.getPublishingSettings();
}

@riverpod
Future<SnFediverseAvailabilityResponse> fediverseAvailability(Ref ref) async {
  final client = ref.read(solarNetworkClientProvider);
  return await client.sphere.getFediverseAvailability();
}

@riverpod
List<SnNotificationTopic> notificationTopics(Ref ref) {
  final client = ref.read(solarNetworkClientProvider);
  return client.notifications.getTopics();
}

@riverpod
Future<Map<String, SnNotificationPreferenceLevel>> notificationPreferences(
  Ref ref,
) async {
  final client = ref.read(solarNetworkClientProvider);
  final prefs = await client.notifications.getPreferences();
  return {for (var p in prefs) p.topic: p.preference};
}

@riverpod
Future<List<SnNotificationPushSubscription>> notificationSubscriptions(
  Ref ref,
) async {
  final client = ref.read(solarNetworkClientProvider);
  return await client.notifications.getSubscriptions();
}

@riverpod
bool hasFediverseIdentity(Ref ref) {
  final publishingSettings = ref.watch(publishingSettingsProvider);
  final fediverseAvailability = ref.watch(fediverseAvailabilityProvider);

  final hasDefaultPublisher =
      publishingSettings.whenOrNull(
        data: (settings) => settings.defaultFediversePublisherId != null,
      ) ??
      false;

  final hasAnyEnabledPublisher =
      fediverseAvailability.whenOrNull(
        data: (response) => response.publishers.any((p) => p.isEnabled),
      ) ??
      false;

  return hasDefaultPublisher || hasAnyEnabledPublisher;
}

@riverpod
Future<String> securityPreferencesMode(Ref ref) async {
  final client = ref.read(solarNetworkClientProvider);
  final data = await client.stargate.getSecurityPreferences();
  return (data['mode'] as String?) ?? 'default';
}

/// Account settings backed by `/auth/settings`, `/auth/2fa` and
/// `/auth/passkey`: profile, bound contacts, TOTP and passkeys.
@RoutePage()
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(lkmApiSessionProvider);
    return _AccountSettingsContent(
      key: ValueKey((session, session.identityRevision)),
    );
  }
}

class _AccountSettingsContent extends HookConsumerWidget {
  const _AccountSettingsContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = useState<LkmAccountSettings?>(null);
    final credentials = useState<List<LkmPasskeyCredential>?>(null);
    final me = ref.watch(lkmMeProvider);
    final busy = useState(false);
    final error = useState<String?>(null);

    Future<void> load() async {
      if (!context.mounted) return;
      busy.value = true;
      error.value = null;
      try {
        final api = ref.read(authApiProvider);
        final session = ref.read(lkmApiSessionProvider);
        await Future.wait([
          session.run(api.accountSettings).then((value) {
            if (context.mounted) settings.value = value;
          }),
          session.run(api.passkeyCredentials).then((value) {
            if (context.mounted) credentials.value = value;
          }),
        ]);
      } catch (failure) {
        if (context.mounted) error.value = _describe(failure);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    useEffect(() {
      Future.microtask(load);
      return null;
    }, const []);

    Future<void> run(Future<void> Function() action) async {
      if (!context.mounted || busy.value) return;
      busy.value = true;
      error.value = null;
      try {
        await action();
      } catch (failure) {
        if (context.mounted) error.value = _describe(failure);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> saveProfile(String nickname) => run(() async {
      final account = me.value;
      if (account == null) return;
      final api = ref.read(authApiProvider);
      await ref
          .read(lkmApiSessionProvider)
          .run(() => api.updateProfile(userId: account.id, nickname: nickname));
      if (!context.mounted) return;
      ref.invalidate(lkmMeProvider);
      ref.invalidate(userProfileProvider(account.id));
      if (context.mounted) showSnackBar('authFlow.profileSaved'.tr());
    });

    Future<void> editNickname() async {
      final value = await _askText(
        context,
        title: 'authFlow.nickname'.tr(),
        label: 'authFlow.nickname'.tr(),
        initial: me.value?.nickname ?? '',
        helperText: 'authFlow.nicknameHint'.tr(),
        maxLength: 100,
      );
      if (value == null || value == (me.value?.nickname ?? '').trim()) return;
      await saveProfile(value);
    }

    Future<void> uploadAvatar() => run(() async {
      final account = me.value;
      if (account == null) return;
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty || !context.mounted) return;
      final file = picked.first;
      const maxBytes = 2 * 1024 * 1024;
      if ((await file.length() ?? 0) > maxBytes) {
        throw StateError('authFlow.avatarTooLarge'.tr());
      }
      final bytes = await file.xFile.readAsBytes();
      if (bytes.length > maxBytes) {
        throw StateError('authFlow.avatarTooLarge'.tr());
      }
      if (bytes.isEmpty) throw StateError('authFlow.avatarEmpty'.tr());
      if (!context.mounted) return;
      final api = ref.read(authApiProvider);
      await ref
          .read(lkmApiSessionProvider)
          .run(() => api.uploadAvatar(bytes: bytes, filename: file.name));
      // The upload endpoint already updates Profile.avatar.
      if (!context.mounted) return;
      ref.invalidate(lkmMeProvider);
      ref.invalidate(userProfileProvider(account.id));
      if (context.mounted) showSnackBar('authFlow.avatarUpdated'.tr());
    });

    Future<void> bindContact({required bool email}) async {
      final contact = await _askText(
        context,
        title: (email ? 'authFlow.bindEmail' : 'authFlow.bindPhone').tr(),
        label: (email ? 'authFlow.email' : 'authFlow.phone').tr(),
      );
      if (contact == null || contact.trim().isEmpty) return;
      await run(() async {
        final api = ref.read(authApiProvider);
        email
            ? await api.requestBindEmail(contact)
            : await api.requestBindPhone(contact);
        if (!context.mounted) return;
        final code = await _askText(
          context,
          title: 'authFlow.verify'.tr(),
          label: 'authFlow.codeSentTo'.tr(args: [contact]),
          number: true,
        );
        if (code == null || code.trim().isEmpty || !context.mounted) return;
        email
            ? await api.verifyBindEmail(email: contact, code: code)
            : await api.verifyBindPhone(phone: contact, code: code);
        await load();
      });
    }

    Future<void> bindGithub() => run(() async {
      final bound = await runGithubBind(ref.read(authApiProvider));
      if (!context.mounted) return;
      if (!bound) {
        error.value = 'authFlow.bindFailed'.tr();
        return;
      }
      await load();
    });

    Future<void> unbind(String type) async {
      String? code;
      String? recovery;
      if (settings.value?.has2fa == true) {
        final values = await _askTwoFactor(context);
        if (values == null) return;
        code = values.$1;
        recovery = values.$2;
      }
      await run(() async {
        await ref
            .read(authApiProvider)
            .unbind(type, code: code, recoveryCode: recovery);
        await load();
      });
    }

    Future<void> toggleTotp(bool enable) => run(() async {
      final api = ref.read(authApiProvider);
      if (enable) {
        final result = await showDialog<bool>(
          context: context,
          builder: (_) => const TotpSetupDialog(),
        );
        if (result == true) await load();
        return;
      }
      final values = await _askTwoFactor(context);
      if (values == null || !context.mounted) return;
      await api.disableTotp(code: values.$1, recoveryCode: values.$2);
      await load();
    });

    Future<void> addPasskey() => run(() async {
      final authenticator = PasskeyAuthenticator(debugMode: kDebugMode);
      final options = await ref
          .read(authApiProvider)
          .beginPasskeyRegistration();
      if (!context.mounted) return;
      final pk = options.publicKey;
      final rp = pk['rp'] is Map ? pk['rp'] as Map : const {};
      final user = pk['user'] is Map ? pk['user'] as Map : const {};
      final selection = pk['authenticatorSelection'] is Map
          ? pk['authenticatorSelection'] as Map
          : null;
      final params = (pk['pubKeyCredParams'] as List? ?? const [])
          .whereType<Map>();
      final request = RegisterRequestType(
        challenge: '${pk['challenge'] ?? ''}',
        relyingParty: RelyingPartyType(
          id: '${rp['id'] ?? ''}',
          name: '${rp['name'] ?? ''}',
        ),
        user: UserType(
          id: '${user['id'] ?? ''}',
          name: '${user['name'] ?? ''}',
          displayName: '${user['displayName'] ?? user['name'] ?? ''}',
        ),
        excludeCredentials: (pk['excludeCredentials'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => CredentialType(
                type: '${e['type'] ?? 'public-key'}',
                id: '${e['id'] ?? ''}',
                transports: const [],
              ),
            )
            .toList(growable: false),
        pubKeyCredParams: params
            .map(
              (e) => PubKeyCredParamType(
                type: '${e['type'] ?? 'public-key'}',
                alg: e['alg'] is int ? e['alg'] as int : -7,
              ),
            )
            .toList(growable: false),
        authSelectionType: selection == null
            ? null
            : AuthenticatorSelectionType(
                authenticatorAttachment:
                    selection['authenticatorAttachment'] as String?,
                residentKey: '${selection['residentKey'] ?? 'preferred'}',
                userVerification:
                    '${selection['userVerification'] ?? 'preferred'}',
                requireResidentKey: selection['requireResidentKey'] == true,
              ),
        timeout: pk['timeout'] is int ? pk['timeout'] as int : null,
        attestation: 'none',
      );
      final credential = await authenticator.register(request);
      if (!context.mounted) return;
      await ref
          .read(authApiProvider)
          .completePasskeyRegistration(
            challengeId: options.challengeId,
            rawId: credential.id,
            response: {
              'attestationObject': credential.attestationObject,
              'clientDataJSON': credential.clientDataJSON,
            },
            deviceName: 'Desktop passkey',
          );
      await load();
    });

    Future<void> deletePasskey(LkmPasskeyCredential credential) =>
        run(() async {
          final api = ref.read(authApiProvider);
          final session = ref.read(lkmApiSessionProvider);
          // Let the server's trust window decide when to prompt, rather than
          // collecting a fresh code for every deletion.
          try {
            await session.run(() => api.deletePasskey(credential.id));
          } on ApiException catch (failure) {
            if (failure.code != ApiCode.mfaRequired) rethrow;
            if (!context.mounted) return;
            if (settings.value?.has2fa != true) {
              await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const TotpSetupDialog(),
              );
              await load();
              return;
            }
            final values = await _askTwoFactor(context);
            if (values == null || !context.mounted) return;
            final stepped = await session.run(
              () => api.stepUpTotp(code: values.$1, recoveryCode: values.$2),
            );
            if (stepped.hasTokens) {
              await ref
                  .read(loginControllerProvider.notifier)
                  .adoptTokens(
                    LkmAuthToken(
                      userId: stepped.userId,
                      accountLevel: stepped.accountLevel,
                      accessToken: stepped.accessToken!,
                      refreshToken: stepped.refreshToken ?? '',
                    ),
                    session: session,
                  );
            }
            await session.run(() => api.deletePasskey(credential.id));
          }
          await load();
        });

    final theme = Theme.of(context);
    final has2fa = settings.value?.has2fa ?? false;
    final account = me.value;
    final profileBusy = busy.value || account == null;
    final securityBusy = busy.value || settings.value == null;
    final failure = error.value ?? (me.hasError ? _describe(me.error!) : null);

    Future<void> refresh() async {
      ref.invalidate(lkmMeProvider);
      await load();
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('accountSettings'.tr()),
        actions: [
          IconButton(
            onPressed: busy.value ? null : refresh,
            tooltip: 'refresh'.tr(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: busy.value && settings.value == null
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: SolSpace.page),
                  child: Column(
                    spacing: SolSpace.xl,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (busy.value) const LinearProgressIndicator(),
                      if (failure != null)
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: SolSpace.page,
                            ),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Symbols.error_outline,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                const Gap(12),
                                Expanded(
                                  child: Text(
                                    failure,
                                    style: TextStyle(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: busy.value ? null : refresh,
                                  child: Text('retry'.tr()),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _SettingsSection(
                        title: 'accountProfileTitle',
                        children: [
                          if (account != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 20, 12),
                              child: Row(
                                children: [
                                  IconButton(
                                    tooltip: 'authFlow.uploadAvatar'.tr(),
                                    onPressed: profileBusy
                                        ? null
                                        : uploadAvatar,
                                    icon: ProfilePictureWidget(
                                      imageUrl: userAvatarUrl(
                                        ref.watch(lkmServerUrlProvider),
                                        account.id,
                                        account.avatar,
                                      ),
                                      fallbackName: account.displayName,
                                      radius: 28,
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          account.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        const Gap(4),
                                        Text(
                                          '@${account.username}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (me.isLoading)
                            const LinearProgressIndicator(),
                          ListTile(
                            minLeadingWidth: 44,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 2,
                            ),
                            leading: _buildLeadingIcon(
                              context,
                              Symbols.person_edit,
                            ),
                            title: Text('authFlow.nickname'.tr()),
                            subtitle: Text(
                              account?.displayName ?? 'loading'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: const Icon(Symbols.chevron_right),
                            onTap: profileBusy ? null : editNickname,
                          ),
                          ListTile(
                            minLeadingWidth: 44,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 2,
                            ),
                            leading: _buildLeadingIcon(context, Symbols.image),
                            title: Text('authFlow.uploadAvatar'.tr()),
                            trailing: const Icon(Symbols.chevron_right),
                            onTap: profileBusy ? null : uploadAvatar,
                          ),
                        ],
                      ),
                      _SettingsSection(
                        title: 'accountSecurityTitle',
                        children: [
                          SwitchListTile(
                            secondary: _buildLeadingIcon(
                              context,
                              Symbols.security,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 2,
                            ),
                            value: has2fa,
                            onChanged: securityBusy ? null : toggleTotp,
                            title: Text('authFlow.twoFactor'.tr()),
                            subtitle: Text(
                              settings.value == null
                                  ? (busy.value ? 'loading' : 'failedToLoad')
                                        .tr()
                                  : has2fa
                                  ? 'authFlow.enabled'.tr()
                                  : 'authFlow.disabled'.tr(),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          ExpansionTile(
                            leading: _buildLeadingIcon(context, Symbols.key),
                            title: Text('authFlow.sectionPasskeys'.tr()),
                            subtitle: Text(
                              credentials.value == null
                                  ? (busy.value ? 'loading' : 'failedToLoad')
                                        .tr()
                                  : credentials.value!.isEmpty
                                  ? 'authFlow.passkeyEmpty'.tr()
                                  : '${credentials.value!.length}',
                              style: theme.textTheme.bodySmall,
                            ),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 2,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  spacing: 6,
                                  children: [
                                    for (final credential
                                        in credentials.value ??
                                            const <LkmPasskeyCredential>[])
                                      Container(
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainer,
                                          borderRadius: BorderRadius.circular(
                                            SolRadius.md,
                                          ),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 2,
                                              ),
                                          leading: const CircleAvatar(
                                            child: Icon(Symbols.key, size: 16),
                                          ),
                                          title: Text(credential.deviceName),
                                          subtitle: Text(
                                            credential.createdAt == null
                                                ? credential.credentialId
                                                : '${credential.credentialId} · '
                                                      '${_date(credential.createdAt!)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: IconButton(
                                            tooltip: 'authFlow.delete'.tr(),
                                            onPressed: securityBusy
                                                ? null
                                                : () =>
                                                      deletePasskey(credential),
                                            icon: const Icon(Symbols.delete),
                                          ),
                                        ),
                                      ),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(
                                          SolRadius.md,
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 2,
                                            ),
                                        leading: const Icon(Symbols.add),
                                        title: Text('authFlow.addPasskey'.tr()),
                                        trailing: const Icon(
                                          Symbols.chevron_right,
                                        ),
                                        onTap: securityBusy ? null : addPasskey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _SettingsSection(
                        title: 'accountContactMethod',
                        children: [
                          _BindingRow(
                            icon: Symbols.mail,
                            label: 'authFlow.email'.tr(),
                            value: settings.value?.email,
                            busy: securityBusy,
                            onBind: () => bindContact(email: true),
                            onUnbind: () => unbind('email'),
                          ),
                          _BindingRow(
                            icon: Symbols.phone,
                            label: 'authFlow.phone'.tr(),
                            value: settings.value?.phone,
                            busy: securityBusy,
                            onBind: () => bindContact(email: false),
                            onUnbind: () => unbind('phone'),
                          ),
                          _BindingRow(
                            icon: Symbols.code,
                            label: 'GitHub',
                            value: settings.value?.github,
                            busy: securityBusy,
                            onBind: bindGithub,
                            onUnbind: () => unbind('github'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Rounded group card, mirroring the upstream account settings section: a
/// tinted title strip above a tight list of rows.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SolSpace.page),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SolRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SolSpace.xl,
                SolSpace.lg,
                SolSpace.xl,
                SolSpace.sm,
              ),
              child: Text(
                title.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            ...children,
            const SizedBox(height: SolSpace.sm),
          ],
        ),
      ),
    );
  }
}

Widget _buildLeadingIcon(BuildContext context, IconData icon) {
  final colorScheme = Theme.of(context).colorScheme;
  return Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(SolRadius.md),
    ),
    child: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
  );
}

class _BindingRow extends StatelessWidget {
  const _BindingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.busy,
    required this.onBind,
    required this.onUnbind,
  });

  final IconData icon;
  final String label;
  final String? value;
  final bool busy;
  final VoidCallback? onBind;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bound = value != null && value!.isNotEmpty;
    return ListTile(
      minLeadingWidth: 44,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: _buildLeadingIcon(context, icon),
      title: Text(label),
      subtitle: Text(
        bound ? value! : 'authFlow.notBound'.tr(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: bound
          ? TextButton(
              onPressed: busy ? null : onUnbind,
              child: Text('authFlow.unbind'.tr()),
            )
          : onBind == null
          ? null
          : TextButton(
              onPressed: busy ? null : onBind,
              child: Text('authFlow.bind'.tr()),
            ),
    );
  }
}

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  bool number = false,
  String? initial,
  String? helperText,
  int? maxLength,
}) => showDialog<String>(
  context: context,
  builder: (context) => HookBuilder(
    builder: (context) {
      final controller = useTextEditingController(text: initial);
      final formKey = useMemoized(GlobalKey<FormState>.new);
      void submit() {
        if (formKey.currentState!.validate()) {
          Navigator.pop(context, controller.text.trim());
        }
      }

      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLength: maxLength,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              labelText: label,
              helperText: helperText,
            ),
            validator: (value) =>
                maxLength != null && (value ?? '').runes.length > maxLength
                ? 'authFlow.valueTooLong'.tr(args: ['$maxLength'])
                : null,
            onFieldSubmitted: (_) => submit(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr()),
          ),
          FilledButton(onPressed: submit, child: Text('confirm'.tr())),
        ],
      );
    },
  ),
);

Future<(String?, String?)?> _askTwoFactor(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('authFlow.twoFactorVerify'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('authFlow.twoFactorHint'.tr()),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'authFlow.totpOrRecovery'.tr(),
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text('confirm'.tr()),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty) return null;
  final digits = RegExp(r'^\d{6}$').hasMatch(result);
  return digits ? (result, null) : (null, result);
}

String _describe(Object failure) {
  if (failure is StateError) return failure.message;
  if (failure is ApiException) return failure.message;
  if (failure is ApiTransportException) return failure.message;
  return '$failure';
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

@freezed
sealed class SnPhysicalPassport with _$SnPhysicalPassport {
  const factory SnPhysicalPassport({
    required String id,
    String? label,
    required bool isActive,
    required bool isLocked,
    required bool isEncrypted,
    DateTime? lastSeenAt,
    required DateTime createdAt,
    String? uid,
  }) = _SnPhysicalPassport;

  factory SnPhysicalPassport.fromJson(Map<String, dynamic> json) =>
      _$SnPhysicalPassportFromJson(json);
}

final physicalPassportsProvider =
    FutureProvider.autoDispose<List<SnPhysicalPassport>>((ref) async {
      final client = ref.watch(solarNetworkClientProvider);
      final response = await client.dio.get('/stargate/nfc/tags');
      return (response.data as List)
          .map((e) => SnPhysicalPassport.fromJson(e))
          .toList();
    });

@RoutePage()
class PhysicalPassportScreen extends HookConsumerWidget {
  const PhysicalPassportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passportsAsync = ref.watch(physicalPassportsProvider);
    final user = ref.watch(userInfoProvider);
    final isAdmin = user.value?.isSuperuser == true;

    return AppScaffold(
      appBar: AppBar(
        title: Text('physicalPassports').tr(),
        leading: const AutoLeadingButton(),
        actions: [
          if (isAdmin && _supportsPhysicalPassportScan)
            IconButton(
              icon: const Icon(Symbols.admin_panel_settings),
              tooltip: 'adminRegisterEncryptedTag'.tr(),
              onPressed: () => _showAdminRegisterSheet(context, ref),
            ),
          const Gap(8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(physicalPassportsProvider);
        },
        child: passportsAsync.when(
          data: (passports) {
            if (passports.isEmpty) {
              final canAdd = _supportsPhysicalPassportScan && isAdmin;
              return EmptyState(
                icon: Symbols.badge,
                title: 'physicalPassportsEmpty'.tr(),
                description:
                    (canAdd
                            ? 'physicalPassportsEmptyDescription'
                            : 'physicalPassportsEmptyIssuedByAdmin')
                        .tr(),
                action: canAdd
                    ? FilledButton.icon(
                        onPressed: () => _showAddSheet(context, ref),
                        icon: const Icon(Symbols.add),
                        label: Text('addPhysicalPassport').tr(),
                      )
                    : null,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: passports.length,
              itemBuilder: (context, index) {
                final passport = passports[index];
                return _PhysicalPassportListItem(
                  passport: passport,
                  onTap: () => _showDetailSheet(context, ref, passport),
                );
              },
            );
          },
          error: (error, _) => ResponseErrorWidget(
            error: error,
            onRetry: () => ref.invalidate(physicalPassportsProvider),
          ),
          loading: () => const ResponseLoadingWidget(),
        ),
      ),
      floatingActionButton: passportsAsync.maybeWhen(
        data: (passports) =>
            _supportsPhysicalPassportScan &&
                isAdmin &&
                passports.isNotEmpty &&
                user.value != null
            ? FloatingActionButton.extended(
                onPressed: () => _showAddSheet(context, ref),
                icon: const Icon(Symbols.add),
                label: Text('addPhysicalPassport').tr(),
              )
            : null,
        orElse: () => null,
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    if (!_supportsPhysicalPassportScan) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => const _AddPhysicalPassportSheet(),
    ).then((_) {
      ref.invalidate(physicalPassportsProvider);
    });
  }

  void _showDetailSheet(
    BuildContext context,
    WidgetRef ref,
    SnPhysicalPassport passport,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => _PhysicalPassportDetailSheet(passport: passport),
    ).then((_) {
      ref.invalidate(physicalPassportsProvider);
    });
  }

  void _showAdminRegisterSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => const _AdminRegisterEncryptedTagSheet(),
    ).then((_) {
      ref.invalidate(physicalPassportsProvider);
    });
  }
}

class _PhysicalPassportListItem extends StatelessWidget {
  final SnPhysicalPassport passport;
  final VoidCallback onTap;

  const _PhysicalPassportListItem({
    required this.passport,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SolRadius.card),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SolRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: passport.isLocked
                      ? colorScheme.tertiaryContainer
                      : colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  passport.isLocked ? Symbols.lock : Symbols.badge,
                  color: passport.isLocked
                      ? colorScheme.onTertiaryContainer
                      : colorScheme.onPrimaryContainer,
                ),
              ),
              const Gap(16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passport.label ?? 'physicalPassportUnnamed'.tr(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (passport.lastSeenAt != null) ...[
                      Text(
                        'physicalPassportLastSeen'.tr(
                          args: [
                            _formatRelativeTime(context, passport.lastSeenAt!),
                          ],
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (!passport.isActive)
                          _StatusChip(
                            label: 'physicalPassportInactive'.tr(),
                            color: colorScheme.onErrorContainer,
                            icon: Symbols.error,
                          ),
                        if (passport.isLocked)
                          _StatusChip(
                            label: 'physicalPassportLocked'.tr(),
                            color: colorScheme.onTertiaryContainer,
                            icon: Symbols.lock,
                          ),
                        if (passport.isEncrypted)
                          _StatusChip(
                            label: 'physicalPassportEncrypted'.tr(),
                            color: colorScheme.onPrimaryContainer,
                            icon: Symbols.lock,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Symbols.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(BuildContext context, DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return 'timeDaysAgo'.tr(args: [difference.inDays.toString()]);
    } else if (difference.inHours > 0) {
      return 'timeHoursAgo'.tr(args: [difference.inHours.toString()]);
    } else if (difference.inMinutes > 0) {
      return 'timeMinutesAgo'.tr(args: [difference.inMinutes.toString()]);
    } else {
      return 'timeJustNow'.tr();
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Icon(icon, color: color, size: 16),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _AddPhysicalPassportSheet extends ConsumerStatefulWidget {
  const _AddPhysicalPassportSheet();

  @override
  ConsumerState<_AddPhysicalPassportSheet> createState() =>
      _AddPhysicalPassportSheetState();
}

class _AddPhysicalPassportSheetState
    extends ConsumerState<_AddPhysicalPassportSheet> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _uidController = TextEditingController();
  bool _isSubmitting = false;
  bool _isScanning = false;
  String? _scannedUid;
  NFCTag? _scannedTag;

  @override
  void dispose() {
    _labelController.dispose();
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'addPhysicalPassport'.tr(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'addPhysicalPassportDescription'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(24),
              FilledButton.tonalIcon(
                onPressed: !_supportsPhysicalPassportScan || _isScanning
                    ? null
                    : _scanPassport,
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.nfc),
                label: Text(
                  _isScanning ? 'scanning'.tr() : 'scanPhysicalPassport'.tr(),
                ),
              ),
              if (_scannedUid != null) ...[
                const Gap(24),
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Symbols.check_circle,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            const Gap(8),
                            Text(
                              'physicalPassportScanned'.tr(),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const Gap(12),
                        Text(
                          'UID: $_scannedUid',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                        const Gap(12),
                        Text(
                          'Tag Type: ${_scannedTag?.type}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                        const Gap(12),
                        Text('NDEF Type: ${_scannedTag?.ndefType}'),
                      ],
                    ),
                  ),
                ),
              ],
              const Gap(24),
              TextFormField(
                controller: _labelController,
                decoration: InputDecoration(
                  labelText: 'physicalPassportLabel'.tr(),
                  hintText: 'physicalPassportLabelHint'.tr(),
                  prefixIcon: const Icon(Symbols.label),
                ),
                maxLength: 64,
              ),
              const Gap(16),
              TextFormField(
                controller: _uidController,
                decoration: InputDecoration(
                  labelText: 'physicalPassportUid'.tr(),
                  hintText: 'physicalPassportUidHint'.tr(),
                  prefixIcon: const Icon(Symbols.tag),
                ),
                enabled: false,
              ),
              const Gap(24),
              if (_scannedTag?.type == .iso7816)
                Text(
                  'encryptedTagRegsiterHint'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colorScheme.tertiary),
                  textAlign: TextAlign.center,
                )
              else
                FilledButton(
                  onPressed: _isSubmitting || _scannedUid == null
                      ? null
                      : _register,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('registerPhysicalPassport').tr(),
                ),
              const Gap(16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanPassport() async {
    if (!_supportsPhysicalPassportScan) return;
    setState(() => _isScanning = true);

    try {
      final availability = await NfcScanService().checkAvailability();
      if (availability != NFCAvailability.available) {
        if (mounted) {
          showErrorAlert(Exception('nfcNotAvailable'.tr()));
        }
        return;
      }

      final tag = await NfcScanService().scanTag();
      final uid = tag.id;

      setState(() {
        _scannedUid = uid;
        _scannedTag = tag;
        _uidController.text = uid;
      });
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      // Always finish NFC session to prevent iOS session leak
      await NfcScanService().finish();
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scannedUid == null) return;

    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(solarNetworkClientProvider);
      final response = await client.dio.post(
        '/stargate/nfc/tags',
        data: {
          'uid': _scannedUid,
          if (_labelController.text.trim().isNotEmpty)
            'label': _labelController.text.trim(),
        },
      );
      final passport = SnPhysicalPassport.fromJson(response.data);
      ref.invalidate(physicalPassportsProvider);

      if (!mounted) return;

      Navigator.of(context).pop();
      showSnackBar('physicalPassportRegistered'.tr());
      await _showWriteDeepLinkSheet(_scannedTag!, passport);
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showWriteDeepLinkSheet(
    NFCTag tag,
    SnPhysicalPassport passport,
  ) async {
    bool isWriting = true;
    bool writeSuccess = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      enableDrag: false,
      isDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          if (isWriting) {
            _performWrite(tag, passport)
                .then((result) {
                  if (ctx.mounted) {
                    setSheetState(() {
                      isWriting = false;
                      writeSuccess = result;
                    });
                  }
                })
                .catchError((e) {
                  if (ctx.mounted) {
                    setSheetState(() {
                      isWriting = false;
                      writeSuccess = false;
                    });
                  }
                });
          }

          return SheetScaffold(
            heightFactor: 0.4,
            titleText: 'nfcWritingDeepLink'.tr(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isWriting) ...[
                    const CircularProgressIndicator().center(),
                    const Gap(16),
                    Text('nfcTapToWrite'.tr()),
                  ] else ...[
                    Icon(
                      writeSuccess ? Symbols.check_circle : Symbols.error,
                      size: 48,
                      color: writeSuccess
                          ? Theme.of(ctx).colorScheme.primary
                          : Theme.of(ctx).colorScheme.error,
                    ),
                    const Gap(16),
                    Text(
                      writeSuccess
                          ? 'nfcWriteSuccess'.tr()
                          : 'nfcWriteFailed'.tr(),
                    ),
                    const Gap(24),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('done').tr(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _performWrite(NFCTag tag, SnPhysicalPassport passport) async {
    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        return false;
      }

      await FlutterNfcKit.poll(iosAlertMessage: 'nfcTapToWrite'.tr());

      final deepLink = 'lkm://phpass/${passport.id}';
      final uriRecord = ndef.UriRecord.fromUri(Uri.parse(deepLink));
      await FlutterNfcKit.writeNDEFRecords([uriRecord]);

      await FlutterNfcKit.finish(iosAlertMessage: 'Success');
      return true;
    } catch (e) {
      await FlutterNfcKit.finish(iosErrorMessage: e.toString());
      return false;
    }
  }
}

class _PhysicalPassportDetailSheet extends ConsumerStatefulWidget {
  final SnPhysicalPassport passport;

  const _PhysicalPassportDetailSheet({required this.passport});

  @override
  ConsumerState<_PhysicalPassportDetailSheet> createState() =>
      _PhysicalPassportDetailSheetState();
}

class _PhysicalPassportDetailSheetState
    extends ConsumerState<_PhysicalPassportDetailSheet> {
  late TextEditingController _labelController;
  late bool _isActive;
  bool _isEditing = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.passport.label ?? '');
    _isActive = widget.passport.isActive;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final passport = widget.passport;

    return SheetScaffold(
      titleText: 'physicalPassportDetails'.tr(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: passport.isLocked
                        ? colorScheme.tertiaryContainer
                        : colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    passport.isLocked ? Symbols.lock : Symbols.badge,
                    color: passport.isLocked
                        ? colorScheme.onTertiaryContainer
                        : colorScheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isEditing)
                        TextFormField(
                          controller: _labelController,
                          decoration: InputDecoration(
                            labelText: 'physicalPassportLabel'.tr(),
                            isDense: true,
                          ),
                          maxLength: 64,
                        )
                      else
                        Text(
                          passport.label ?? 'physicalPassportUnnamed'.tr(),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      if (!_isEditing && (passport.uid?.isNotEmpty ?? false))
                        Text(
                          'UID: ${passport.uid}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                        ),
                      if (!passport.isLocked && passport.isEncrypted)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.lock,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const Gap(4),
                              Text(
                                'Encrypted (NTAG424)',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(16),
            if (!passport.isLocked && !passport.isEncrypted) ...[
              FilledButton.tonalIcon(
                onPressed: _isSubmitting ? null : _writePassport,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.edit),
                label: Text('writePhysicalPassport'.tr()),
              ),
              const Gap(8),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Symbols.schedule),
              title: Text('physicalPassportCreatedAt'.tr()),
              subtitle: Text(_formatDateTime(passport.createdAt)),
            ),
            if (passport.lastSeenAt != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Symbols.visibility),
                title: Text('physicalPassportLastSeenAt'.tr()),
                subtitle: Text(_formatDateTime(passport.lastSeenAt!)),
              ),
            const Gap(24),
            if (!passport.isLocked && !_isEditing) ...[
              if (!passport.isEncrypted)
                ...([
                  const Gap(8),
                  FilledButton.tonalIcon(
                    onPressed: _isSubmitting ? null : _writePassport,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.edit),
                    label: Text('writePhysicalPassport'.tr()),
                  ),
                ]),
              FilledButton.tonalIcon(
                onPressed: _isSubmitting ? null : _lockPassport,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.lock),
                label: Text('lockPhysicalPassport'.tr()),
              ),
              const Gap(8),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Symbols.edit),
                label: Text('editPhysicalPassport'.tr()),
              ),
              const Gap(8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                ),
                onPressed: _isSubmitting ? null : _deletePassport,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.delete),
                label: Text('physicalPassportDelete'.tr()),
              ),
            ],
            if (_isEditing) ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _isEditing = false;
                                _labelController.text = passport.label ?? '';
                                _isActive = passport.isActive;
                              });
                            },
                      child: Text('cancel'.tr()),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _saveChanges,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('save'.tr()),
                    ),
                  ),
                ],
              ),
            ],
            const Gap(16),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(solarNetworkClientProvider);
      await client.dio.patch(
        '/stargate/nfc/tags/${widget.passport.id}',
        data: {
          'label': _labelController.text.trim().isEmpty
              ? null
              : _labelController.text.trim(),
          'is_active': _isActive,
        },
      );
      ref.invalidate(physicalPassportsProvider);
      if (mounted) {
        setState(() => _isEditing = false);
        showSnackBar('physicalPassportUpdated'.tr());
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _lockPassport() async {
    final confirm = await showConfirmAlert(
      'physicalPassportLockConfirm'.tr(),
      'lockPhysicalPassport'.tr(),
    );
    if (!confirm) return;

    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(solarNetworkClientProvider);
      await client.dio.post('/stargate/nfc/tags/${widget.passport.id}/lock');
      ref.invalidate(physicalPassportsProvider);
      if (mounted) {
        showSnackBar('physicalPassportLocked'.tr());
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _deletePassport() async {
    final confirm = await showConfirmAlert(
      'physicalPassportDeleteConfirm'.tr(),
      'physicalPassportDelete'.tr(),
      isDanger: true,
    );
    if (!confirm) return;

    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(solarNetworkClientProvider);
      await client.dio.delete('/stargate/nfc/tags/${widget.passport.id}');
      ref.invalidate(physicalPassportsProvider);
      if (mounted) {
        showSnackBar('physicalPassportDeleted'.tr());
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _writePassport() async {
    if (!_supportsPhysicalPassportScan) return;
    setState(() => _isSubmitting = true);

    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        if (mounted) {
          showErrorAlert(Exception('nfcNotAvailable'.tr()));
        }
        return;
      }

      await FlutterNfcKit.poll(iosAlertMessage: 'nfcTapToWrite'.tr());

      final deepLink = 'lkm://phpass/${widget.passport.id}';
      final uriRecord = ndef.UriRecord.fromUri(Uri.parse(deepLink));
      await FlutterNfcKit.writeNDEFRecords([uriRecord]);

      await FlutterNfcKit.finish(iosAlertMessage: 'Success');

      if (mounted) {
        showSnackBar('nfcTagWritten'.tr());
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        await FlutterNfcKit.finish(iosErrorMessage: e.toString());
        showErrorAlert(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat.yMMMd().add_Hm().format(dateTime.toLocal());
  }
}

class _AdminRegisterEncryptedTagSheet extends ConsumerStatefulWidget {
  const _AdminRegisterEncryptedTagSheet();

  @override
  ConsumerState<_AdminRegisterEncryptedTagSheet> createState() =>
      _AdminRegisterEncryptedTagSheetState();
}

class _AdminRegisterEncryptedTagSheetState
    extends ConsumerState<_AdminRegisterEncryptedTagSheet> {
  final _formKey = GlobalKey<FormState>();
  final _uidController = TextEditingController();
  final _sunKeyController = TextEditingController();
  final _assignedUserIdController = TextEditingController();
  bool _isSubmitting = false;
  bool _isScanning = false;
  String? _scannedUid;
  NFCTag? _scannedTag;

  @override
  void dispose() {
    _uidController.dispose();
    _sunKeyController.dispose();
    _assignedUserIdController.dispose();
    super.dispose();
  }

  void _generateSunKey() {
    final rng = Random.secure();
    final key = List.generate(16, (_) => rng.nextInt(256));
    _sunKeyController.text = base64Encode(key);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'adminRegisterEncryptedTag'.tr(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'adminRegisterEncryptedTagDescription'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(24),
              FilledButton.tonalIcon(
                onPressed: _isScanning ? null : _scanTag,
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.nfc),
                label: Text(_isScanning ? 'scanning'.tr() : 'scanTag'.tr()),
              ),
              if (_scannedUid != null) ...[
                const Gap(16),
                Card(
                  elevation: 0,
                  color: colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Symbols.check_circle,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            const Gap(8),
                            Text(
                              'tagScanned'.tr(),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const Gap(12),
                        Text(
                          'UID: $_scannedUid',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                        const Gap(12),
                        Text(
                          'Tag Type: ${_scannedTag?.type}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Gap(24),
              TextFormField(
                controller: _uidController,
                decoration: InputDecoration(
                  labelText: 'tagUid'.tr(),
                  hintText: 'tagUidHint'.tr(),
                  prefixIcon: const Icon(Symbols.tag),
                ),
                enabled: false,
              ),
              const Gap(16),
              TextFormField(
                controller: _sunKeyController,
                decoration: InputDecoration(
                  labelText: 'physicalPassportSunKey'.tr(),
                  hintText: 'physicalPassportSunKeyHint'.tr(),
                  prefixIcon: const Icon(Symbols.key),
                  suffixIcon: IconButton(
                    icon: const Icon(Symbols.autorenew),
                    tooltip: 'generateKey'.tr(),
                    onPressed: _generateSunKey,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'sunKeyRequired'.tr();
                  }
                  return null;
                },
              ),
              Text(
                'physicalPassportSunKeyDescription'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ).padding(horizontal: 8, top: 4),
              const Gap(16),
              TextFormField(
                controller: _assignedUserIdController,
                decoration: InputDecoration(
                  labelText: 'assignedUserId'.tr(),
                  hintText: 'assignedUserIdHint'.tr(),
                  prefixIcon: const Icon(Symbols.person),
                ),
              ),
              Text(
                'assignedUserIdDescription'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ).padding(horizontal: 8, top: 4),
              const Gap(32),
              FilledButton(
                onPressed: _isSubmitting || _scannedUid == null
                    ? null
                    : _registerEncryptedTag,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('registerEncryptedTag').tr(),
              ),
              const Gap(16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scanTag() async {
    if (!_supportsPhysicalPassportScan) return;
    setState(() => _isScanning = true);

    try {
      final availability = await NfcScanService().checkAvailability();
      if (availability != NFCAvailability.available) {
        if (mounted) {
          showErrorAlert(Exception('nfcNotAvailable'.tr()));
        }
        return;
      }

      final tag = await NfcScanService().scanTag();
      final uid = tag.id;

      setState(() {
        _scannedUid = uid;
        _scannedTag = tag;
        _uidController.text = uid;
      });
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      // Always finish NFC session to prevent iOS session leak
      await NfcScanService().finish();
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _registerEncryptedTag() async {
    if (!_formKey.currentState!.validate()) return;
    if (_scannedUid == null) return;

    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(solarNetworkClientProvider);
      await client.dio.post(
        '/stargate/admin/nfc/tags',
        data: {
          'uid': _scannedUid,
          'sun_key': _sunKeyController.text.trim(),
          if (_assignedUserIdController.text.trim().isNotEmpty)
            'assigned_user_id': _assignedUserIdController.text.trim(),
        },
      );
      ref.invalidate(physicalPassportsProvider);

      if (!mounted) return;

      Navigator.of(context).pop();
      showSnackBar('encryptedTagRegistered'.tr());
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _ClaimByUidSheet extends ConsumerStatefulWidget {
  const _ClaimByUidSheet();

  @override
  ConsumerState<_ClaimByUidSheet> createState() => _ClaimByUidSheetState();
}

class _ClaimByUidSheetState extends ConsumerState<_ClaimByUidSheet> {
  final _formKey = GlobalKey<FormState>();
  final _uidController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SheetScaffold(
      titleText: 'claimEncryptedTag'.tr(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'claimEncryptedTagDescription'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(24),
              TextFormField(
                controller: _uidController,
                decoration: InputDecoration(
                  labelText: 'tagUid'.tr(),
                  hintText: 'claimTagUidHint'.tr(),
                  prefixIcon: const Icon(Symbols.tag),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'tagUidRequired'.tr();
                  }
                  return null;
                },
              ),
              const Gap(32),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _claimTag,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.card_membership),
                label: Text('claimTag').tr(),
              ),
              const Gap(16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _claimTag() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(solarNetworkClientProvider);
      await client.dio.post(
        '/stargate/nfc/tags/claim',
        data: {'uid': _uidController.text.trim().toUpperCase()},
      );
      ref.invalidate(physicalPassportsProvider);

      if (!mounted) return;

      Navigator.of(context).pop();
      showSnackBar('tagClaimed'.tr());
    } catch (e) {
      if (mounted) {
        showErrorAlert(e);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

@freezed
sealed class SnScanResult with _$SnScanResult {
  const factory SnScanResult({
    required String id,
    required SnAccount? account,
    @Default(false) bool isFriend,
    @Default(false) bool isClaimed,
    @Default([]) List<String> actions,
  }) = _SnScanResult;

  factory SnScanResult.fromJson(Map<String, dynamic> json) =>
      _$SnScanResultFromJson(json);
}
