import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:island/chat/tinode/tinode_client.dart';
import 'package:island/core/api/api_providers.dart';

/// Public Tinode client API key, generated once by `keygen` alongside the
/// server-side `api_key_salt` (see deploy/tinode). Build with
/// `--dart-define=TINODE_API_KEY=…`.
const kTinodeApiKey = String.fromEnvironment('TINODE_API_KEY');

/// The Tinode websocket endpoint on the LKM host: `/v0/*` is proxied by the
/// gateway to the chat server.
Uri? tinodeEndpoint(Uri serverUrl) {
  if (serverUrl.host.isEmpty) return null;
  return serverUrl.replace(
    scheme: switch (serverUrl.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => serverUrl.scheme,
    },
    path: '/v0/channels',
    query: null,
    fragment: null,
  );
}

final tinodeApiKeyProvider = Provider<String>((ref) => kTinodeApiKey);

/// A connected Tinode client for the current LKM session, or null when the
/// user is signed out or no API key was compiled in.
///
/// Kept alive for the session: the chat backend shares one connection and
/// re-creates it when the server address or token changes.
///
/// The session forwards the LKM access token to the auth bridge, which maps
/// the LKM account to a Tinode uid on first login.
final tinodeClientProvider = FutureProvider<TinodeClient?>((ref) async {
  final session = ref.watch(lkmApiSessionProvider);
  final serverUrl = ref.watch(lkmServerUrlProvider);
  final apiKey = ref.watch(tinodeApiKeyProvider);
  final token = session.tokens?.accessToken;
  if (!session.isSignedIn || token == null || apiKey.isEmpty) return null;

  final endpoint = tinodeEndpoint(Uri.parse(serverUrl));
  if (endpoint == null) return null;

  final client = TinodeClient(endpoint: endpoint, apiKey: apiKey);
  ref.onDispose(client.close);
  await client.connect(token);
  return client;
});
