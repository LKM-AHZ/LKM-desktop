import 'package:auto_route/auto_route.dart';

import 'package:island/posts/screens/post_detail.dart';

/// Legacy content detail route; the implementation lives in the post detail
/// screen beside the Solar one.
@RoutePage()
class ContentDetailScreen extends ContentDetailPane {
  const ContentDetailScreen({super.key, required super.id});
}
