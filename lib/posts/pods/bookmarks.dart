import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/core/network.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

final bookmarkStatusProvider = FutureProvider.family<SnPostBookmark?, String>((
  ref,
  postId,
) {
  ref.keepAlive();
  final client = ref.read(solarNetworkClientProvider);
  return client.sphere.getPostBookmark(postId);
});

Future<void> toggleBookmark(
  WidgetRef ref, {
  required String postId,
  required bool currentlyBookmarked,
}) async {
  final client = ref.read(solarNetworkClientProvider);
  if (currentlyBookmarked) {
    await client.sphere.unbookmarkPost(postId);
  } else {
    await client.sphere.bookmarkPost(postId);
  }
  ref.invalidate(bookmarkStatusProvider(postId));
}
