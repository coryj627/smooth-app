/// Everything outside the app that the audit replaces: the Open Food Facts
/// servers, image downloads and the platform plugins.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// One request the app made, and how it was answered.
typedef Answer = http.Response? Function(http.Request request);

/// Stands in for every server the app talks to through `package:http`.
///
/// Nothing leaves the machine: a request no route answers gets a 404 and is
/// listed in [unanswered].
class FakeServers {
  final List<Answer> routes = <Answer>[];
  final List<String> log = <String>[];
  final Set<String> unanswered = <String>{};

  /// When set, every request fails as it does without a connection.
  bool offline = false;

  /// While set, requests wait: the server is slow.  Complete it to answer.
  Completer<void>? slow;

  http.Client get client => MockClient((http.Request request) async {
    log.add('${request.method} ${request.url}');
    await slow?.future;
    if (offline) {
      throw const SocketException('Failed host lookup (a11y harness: offline)');
    }
    for (final Answer route in routes) {
      final http.Response? response = route(request);
      if (response != null) {
        return response;
      }
    }
    unanswered.add('${request.method} ${request.url.replace(query: '')}');
    return http.Response('{}', 404);
  });

  static http.Response json(Object? body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
    },
  );
}

/// Answers every `Image.network` / `NetworkImage` request with [bytes].
class FakeImageHttpClient extends Fake implements HttpClient {
  FakeImageHttpClient(this.bytes);

  final List<int> bytes;
  final List<String> requested = <String>[];

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url.toString());
    return _FakeImageRequest(bytes);
  }
}

class _FakeImageRequest extends Fake implements HttpClientRequest {
  _FakeImageRequest(this.bytes);

  final List<int> bytes;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeImageResponse(bytes);
}

class _FakeHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeImageResponse extends Fake implements HttpClientResponse {
  _FakeImageResponse(this.bytes);

  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onDone: onDone,
    onError: onError,
    cancelOnError: cancelOnError,
  );
}

/// `path_provider` answered with one scratch directory per test process.
class ScratchPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  ScratchPathProvider(this.root);

  final Directory root;

  String _dir(String name) {
    final Directory dir = Directory('${root.path}/$name')
      ..createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => _dir('tmp');
  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');
  @override
  Future<String?> getLibraryPath() async => _dir('library');
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');
  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');
  @override
  Future<String?> getExternalStoragePath() async => _dir('external');
  @override
  Future<List<String>?> getExternalCachePaths() async => <String>[
    _dir('external-cache'),
  ];
  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => <String>[_dir('external')];
  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');
}

/// Method channels of plugins with no implementation under `flutter test`.
///
/// Each call is logged; [answers] maps `channel/method` to a result.  A call
/// with no entry returns null, which is what most plugins accept as "done".
class FakeChannels {
  final List<String> calls = <String>[];
  final Map<String, Object? Function(Object? arguments)> answers =
      <String, Object? Function(Object? arguments)>{};

  void install(Iterable<String> channels) {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final String name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (
        MethodCall call,
      ) async {
        final String key = '$name/${call.method}';
        calls.add(key);
        final Object? Function(Object?)? answer = answers[key];
        return answer?.call(call.arguments);
      });
    }
  }
}
