import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/projects_api.dart';
import 'package:island/core/api/qa_api.dart';
import 'package:island/community/feed_links.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'code': 0,
        'data': {'url': '/api/v1/content/qa/questions/q1/images/i1'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test(
    'image uploads use idempotent image IDs and multipart form data',
    () async {
      final adapter = _Adapter();
      final api = QaApi(
        ApiClient(
          serverUrl: 'http://localhost:8000',
          dio: Dio()..httpClientAdapter = adapter,
        ),
      );
      expect(
        await api.uploadImage(
          'q1',
          imageId: 'i1',
          bytes: Uint8List.fromList([1, 2]),
          filename: 'photo.png',
        ),
        endsWith('/images/i1'),
      );
      final request = adapter.requests.single;
      expect(request.path, '/content/qa/questions/q1/images');
      final form = request.data as FormData;
      expect(form.fields.toMap()['image_id'], 'i1');
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'photo.png');
    },
  );
  test(
    'project requests carry member claims without inventing recruitment fields',
    () async {
      final adapter = _Adapter();
      await ProjectsApi(
        ApiClient(
          serverUrl: 'http://localhost:8000',
          dio: Dio()..httpClientAdapter = adapter,
        ),
      ).apply(
        title: 'A',
        summary: 'B',
        description: 'C',
        memberClaims: [
          {'display_name': 'Ada', 'role_in_project': 'Design'},
        ],
      );
      expect(adapter.requests.single.path, '/projects/applications');
      expect((adapter.requests.single.data as Map)['member_claims'], [
        {'display_name': 'Ada', 'role_in_project': 'Design'},
      ]);
    },
  );
  test('notification links require the exact configured origin', () {
    expect(
      parseFeedRoute(
        'https://site.example:8443/files/f1',
        serverHost: 'https://site.example:8443',
      )?.kind,
      FeedRouteKind.file,
    );
    expect(
      parseFeedRoute(
        'https://site.example/files/f1',
        serverHost: 'https://site.example:8443',
      ),
      isNull,
    );
    expect(
      parseFeedRoute(
        '//site.example/files/f1',
        serverHost: 'https://site.example',
      ),
      isNull,
    );
  });
}

extension on List<MapEntry<String, String>> {
  Map<String, String> toMap() => Map.fromEntries(this);
}
