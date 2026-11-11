/// Launches the real app ([SmoothApp], through the app's own
/// `launchSmoothApp`) over a fake backend, and drives it as a user would.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_store_shared/app_store_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:scanner_shared/scanner_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/data_models/continuous_scan_model.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/data_models/product_list.dart';
import 'package:smooth_app/data_models/product_preferences.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/dao_product_list.dart';
import 'package:smooth_app/database/dao_string_list.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/helpers/analytics_helper.dart';
import 'package:smooth_app/helpers/entry_points_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/l10n/app_localizations_en.dart';
import 'package:smooth_app/main.dart' as app;
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/onboarding/onboarding_flow_navigator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_backend.dart';
import 'fixtures.dart';
import 'harness.dart';

/// The app's English strings, for finders.
final AppLocalizations l10n = AppLocalizationsEn();

/// What a test starts from.
class Start {
  const Start({
    this.onboarding = OnboardingPage.ONBOARDING_COMPLETE,
    this.signedIn = false,
    this.history = const <String>[],
    this.scanned = const <String>[],
    this.userLists = const <String, List<String>>{},
    this.searchHistory = const <String>[],
    this.offline = false,
    this.cameraPermission = 'granted',
    this.hasCamera = true,
    this.prefs = const <String, Object>{},
  });

  /// The onboarding page the user last reached.
  final OnboardingPage onboarding;

  /// Whether an account's credentials are stored on the device.
  final bool signedIn;

  /// Barcodes of the products the user looked at, oldest first.
  final List<String> history;

  /// Barcodes in the current scan session, oldest first.
  final List<String> scanned;

  /// The user's own lists.
  final Map<String, List<String>> userLists;

  final List<String> searchHistory;

  /// No connection: every request fails.
  final bool offline;

  /// `granted`, `denied` or `permanentlyDenied`.
  final String cameraPermission;

  /// Whether the device has a camera at all.
  final bool hasCamera;

  /// Extra shared preferences.
  final Map<String, Object> prefs;
}

/// The one app instance of this test isolate, and everything around it.
abstract final class Smooth {
  static bool _launched = false;
  static late Directory scratch;
  static final FakeServers servers = FakeServers();
  static final FakeChannels channels = FakeChannels();
  static late FakeImageHttpClient images;
  static late LocalDatabase db;
  static String cameraPermission = 'granted';

  /// The screen audited last, for exceptions thrown while leaving it.
  static String? lastScreen;
  static late ErrorWidgetBuilder _errorWidgetBuilder;
  static FlutterExceptionHandler? _onError;

  /// Framework-caught errors since the last [takeErrors], Rive's excepted.
  static final List<String> errors = <String>[];

  static List<String> takeErrors(WidgetTester tester) {
    takeExceptions(tester);
    final List<String> result = List<String>.of(errors);
    errors.clear();
    return result;
  }

  /// Rive animations that could not be drawn since the last [takeRiveGaps].
  static int _riveGaps = 0;

  static int takeRiveGaps() {
    final int result = _riveGaps;
    _riveGaps = 0;
    return result;
  }

  static BuildContext context(WidgetTester tester) =>
      tester.element(find.byType(MaterialApp));

  static T read<T>(WidgetTester tester) =>
      Provider.of<T>(context(tester), listen: false);

  static void _installPlatform() {
    scratch = Directory.systemTemp.createTempSync('smooth_app_a11y_');
    PathProviderPlatform.instance = ScratchPathProvider(scratch);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    channels.answers['dev.fluttercommunity.plus/package_info/getAll'] = (_) =>
        <String, Object?>{
          'appName': 'Open Food Facts',
          'packageName': 'org.openfoodfacts.scanner',
          'version': '4.20.0',
          'buildNumber': '734',
          'buildSignature': '',
          'installerStore': null,
        };
    // permission_handler: 0 denied, 1 granted, 4 permanently denied.
    int status() => switch (cameraPermission) {
      'granted' => 1,
      'permanentlyDenied' => 4,
      _ => 0,
    };
    const String permissions = 'flutter.baseflow.com/permissions/methods';
    channels.answers['$permissions/checkPermissionStatus'] = (_) => status();
    channels.answers['$permissions/requestPermissions'] = (Object? arguments) =>
        <int, int>{
          for (final Object? p in arguments! as List<Object?>)
            p! as int: status(),
        };
    channels.answers['$permissions/shouldShowRequestPermissionRationale'] = (
      _,
    ) => false;
    channels.answers['$permissions/openAppSettings'] = (_) => true;
    channels.answers['dev.fluttercommunity.plus/connectivity/check'] = (_) =>
        <String>['wifi'];
    channels.answers['plugins.flutter.io/url_launcher/canLaunch'] = (_) => true;
    channels.answers['plugins.flutter.io/url_launcher/launch'] = (_) => true;
    channels.install(<String>[
      'dev.fluttercommunity.plus/package_info',
      'dev.fluttercommunity.plus/device_info',
      permissions,
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/share',
      'plugins.flutter.io/url_launcher',
      'plugins.flutter.io/image_picker',
      'flutter_native_splash',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'com.spencerccf.app_settings/methods',
      'dev.britannio.in_app_review',
      'flutter_email_sender',
    ]);

    images = FakeImageHttpClient(
      File('test/a11y/support/product_photo.png').readAsBytesSync(),
    );
    servers.routes.addAll(defaultRoutes());

    // A Rive animation needs the native Rive renderer, which `flutter test`
    // does not have.  The widget's build throws; in its place goes an empty
    // box of the size the animation would fill, which is what the app's own
    // "animation failed to load" branch shows.  Every other build error
    // keeps Flutter's red error box.
    //
    // The failed animation loader also breaks the diagnostics of the
    // provider that holds it (`RiveAnimationsLoader`), which the audit would
    // read for every finding below it; see [attributeToLibExcept].
    attributeToLibExcept(<String>[
      'lib/generic_lib/animations/rive_animation.dart',
    ]);
    _errorWidgetBuilder = ErrorWidget.builder;
    final ErrorWidgetBuilder previous = ErrorWidget.builder;
    // Every error the framework catches, one by one: `takeException` only
    // keeps the first and a count.  All are still forwarded.
    _onError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (!isRiveError(details.exception)) {
        errors.add(describeException(details.exception));
      }
      _onError?.call(details);
    };
    ErrorWidget.builder = (FlutterErrorDetails details) {
      if (isRiveError(details.exception)) {
        _riveGaps++;
        return LayoutBuilder(
          builder: (_, BoxConstraints constraints) => SizedBox(
            width: constraints.hasBoundedWidth ? constraints.maxWidth : 0,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
        );
      }
      return previous(details);
    };
  }

  static bool isRiveError(Object exception) {
    final String text = exception.toString();
    return text.contains('makeFlutterFactory') ||
        text.contains('librive_native') ||
        text.contains("is not a subtype of type 'FileLoader'");
  }

  /// Starts the app on a device in the state [start] describes.
  ///
  /// Once per test process: the app keeps its preferences, database and
  /// router in statics, and disposes some of them when its widget tree is
  /// taken down, so it cannot be started twice.
  static Future<void> launch(WidgetTester tester, Start start) async {
    if (_launched) {
      throw StateError('a11y harness: the app can be launched once per file');
    }
    _launched = true;
    usePhoneView(tester);
    _installPlatform();
    debugNetworkImageHttpClientProvider = () => images;
    cameraPermission = start.cameraPermission;

    SharedPreferences.setMockInitialValues(<String, Object>{
      'lastVisitedOnboardingPage': start.onboarding.index,
      if (start.onboarding != OnboardingPage.NOT_STARTED) ...<String, Object>{
        // What the onboarding leaves behind: the consent answer.
        'user_tracking': false,
        'crash_reports': false,
      },
      ...start.prefs,
    });
    FlutterSecureStorage.setMockInitialValues(
      start.signedIn
          ? <String, String>{'user_id': kUserId, 'pasword': kPassword}
          : <String, String>{},
    );
    await tester.runAsync(() async {
      await databaseFactory.setDatabasesPath('${scratch.path}/db');
      // What the app's own widget tests do (test/tests_utils/mocks.dart,
      // `mockMatomo`): the analytics client exists, opted out and with its
      // timers stopped.  Without it every page that reports a page view
      // throws while building.
      await AnalyticsHelper.initMatomo(
        false,
        dispatchSettings: const DispatchSettings.nonPersistent(),
      );
      await MatomoTracker.instance.setOptOut(optOut: true);
      MatomoTracker.instance.dequeueTimer.cancel();
      MatomoTracker.instance.pingTimer?.cancel();
      await app.launchSmoothApp(
        // The app's own scanner for development: no camera preview, no
        // barcode engine.
        barcodeScanner: start.hasCamera
            ? const MockedScanner()
            : const _NoCameraScanner(),
        appStore: const MockedAppStore(),
        storeLabel: StoreLabel.Test,
        scannerLabel: ScannerLabel.Test,
        // The app's own mode for tests: analytics and crash reports off,
        // no native splash screen, no debug banner.
        screenshots: true,
      );
    });
    await settle(tester);
    db = read<LocalDatabase>(tester);

    // The app skips this step in its screenshot mode: the first run sets the
    // default importance of each food preference.
    await tester.runAsync(
      () => UserPreferences.getUserPreferencesSync().init(
        read<ProductPreferences>(tester),
      ),
    );
    await device(tester, start);
  }

  /// Puts the products, lists and search history of [start] on the device,
  /// replacing what is there, while the app runs.
  static Future<void> device(WidgetTester tester, Start start) async {
    final ContinuousScanModel scanModel = read<ContinuousScanModel>(tester);
    await real(tester, () async {
      await DaoProduct(db).deleteAll();
      final DaoProductList daoProductList = DaoProductList(db);
      for (final String name in daoProductList.getUserLists()) {
        await daoProductList.delete(ProductList.user(name));
      }
      await daoProductList.clear(ProductList.history());
      await daoProductList.clear(ProductList.scanSession());
      await daoProductList.clear(ProductList.scanHistory());
      final DaoStringList daoStringList = DaoStringList(db);
      for (final String item in List<String>.of(
        daoStringList.getAll(DaoStringList.keySearchProductHistory),
      )) {
        await daoStringList.remove(DaoStringList.keySearchProductHistory, item);
      }

      // Every fixture product the state mentions is already on the device,
      // as it is after the user has looked at it once.
      final Set<String> barcodes = <String>{
        ...start.history,
        ...start.scanned,
        for (final List<String> list in start.userLists.values) ...list,
      };
      final DaoProduct daoProduct = DaoProduct(db);
      for (final String barcode in barcodes) {
        await daoProduct.put(
          product(barcode),
          OpenFoodFactsLanguage.ENGLISH,
          productType: ProductType.food,
        );
      }
      for (final String barcode in start.history) {
        await daoProductList.push(ProductList.history(), barcode);
      }
      for (final String barcode in start.scanned) {
        await daoProductList.push(ProductList.scanSession(), barcode);
        await daoProductList.push(ProductList.scanHistory(), barcode);
      }
      for (final MapEntry<String, List<String>> entry
          in start.userLists.entries) {
        final ProductList list = ProductList.user(entry.key);
        await daoProductList.put(list);
        for (final String barcode in entry.value) {
          await daoProductList.set(list, barcode, true);
        }
      }
      for (final String query in start.searchHistory) {
        await daoStringList.add(DaoStringList.keySearchProductHistory, query);
      }
      await scanModel.refresh();
    });
    servers.offline = start.offline;
    db.notifyListeners();
    await settle(tester);
  }

  /// Back to the first page, with nothing open over it.
  static Future<void> home(WidgetTester tester) async {
    AppNavigator.of(context(tester)).clearStack();
    await tester.pump();
    await settle(tester);
    // Each tab keeps its own stack of pages; tapping a tab twice empties it.
    // Ends on the scan tab, where the app opens.
    for (final String tab in <String>[
      l10n.list_navbar_label,
      l10n.profile_navbar_label,
      l10n.scan_navbar_label,
    ]) {
      for (var i = 0; i < 2 && present(find.text(tab)); i++) {
        await tester.tap(find.text(tab).last, warnIfMissed: false);
        await tester.pump();
        await settle(tester, rounds: 1);
      }
    }
  }

  /// Takes the app down so that its timers and animations stop.
  static Future<void> shutDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(minutes: 11));
    takeExceptions(tester);
    debugNetworkImageHttpClientProvider = null;
    ErrorWidget.builder = _errorWidgetBuilder;
    FlutterError.onError = _onError;
  }
}

/// The app's [MockedScanner] on a device with no camera.
class _NoCameraScanner extends MockedScanner {
  const _NoCameraScanner();

  @override
  Future<bool> hasCamera({required bool front}) async => false;
}

/// One part of a walk.  A part that throws is recorded as failed and the
/// walk goes on with the next one from the first page.
typedef Part = Future<void> Function(WidgetTester tester);

/// Declares the one test of a file: the app in state [start], then each of
/// [parts] in order.
///
/// `A11Y_ONLY=name,name` runs only those parts (for writing a walk).
void walk(String description, Start start, Map<String, Part> parts) {
  final Set<String>? only = Platform.environment['A11Y_ONLY']
      ?.split(',')
      .toSet();
  testWidgets(description, (WidgetTester tester) async {
    final Map<String, String> failed = <String, String>{};
    // An error nobody catches (thrown from a timer of the app, say) would
    // fail the test on the spot.  It is recorded with the screen instead.
    await runZonedGuarded(
      () => http.runWithClient(() async {
        await Smooth.launch(tester, start);
        for (final MapEntry<String, Part> part in parts.entries) {
          if (only != null && !only.contains(part.key)) {
            continue;
          }
          try {
            await part.value(tester);
          } on Object catch (error, stack) {
            final String text = error.toString().split('\n').take(6).join('\n');
            failed[part.key] = text;
            ScreenLog.failed('part:${part.key}', text);
            // ignore: avoid_print
            print('a11y PART FAILED ${part.key}: $error\n$stack');
            Smooth.takeErrors(tester);
            await maybeScreenshot(tester, 'failed-${part.key}');
            await maybeDump(tester, 'failed-${part.key}');
          }
          usePhoneViewNow(tester);
          await Smooth.home(tester);
          final String? last = Smooth.lastScreen;
          if (last != null) {
            ScreenLog.exceptionsAfter(last, Smooth.takeErrors(tester));
          }
          Smooth.takeRiveGaps();
          Smooth.lastScreen = null;
        }
        await Smooth.shutDown(tester);
      }, () => Smooth.servers.client),
      (Object error, StackTrace stack) {
        if (!Smooth.isRiveError(error)) {
          Smooth.errors.add('uncaught: ${describeException(error)}');
        }
      },
    );
    if (failed.isNotEmpty) {
      fail('a11y walk: ${failed.length} part(s) did not finish: $failed');
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// Runs [body], which does real input/output (the database, files), next to
/// the running app, and waits for it.
///
/// Not `tester.runAsync(body)`: the app may be in the middle of a database
/// write of its own, started on the test's fake clock.  The database lets
/// one writer in at a time, so [body] would wait for a write that cannot
/// finish while the fake clock stands still.  Here real time and the fake
/// clock advance in turn until [body] is done.
Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
  var done = false;
  late T result;
  Object? error;
  StackTrace? stack;
  unawaited(
    body().then<void>(
      (T value) {
        result = value;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 2000 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 5));
  }
  if (!done) {
    throw TimeoutException('a11y harness: real() did not finish');
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stack!);
  }
  return result;
}

/// Pumps until nothing is animating, or for a few seconds: a page with a
/// progress indicator never settles.
///
/// The database, files and image decoding run on real threads, not on the
/// test's fake clock, so each round first lets real time pass.
Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  var quiet = 0;
  for (var round = 0; round < 60 && quiet < 2; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    var pumped = 0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      pumped++;
      if (i >= 3 && !tester.binding.hasScheduledFrame) {
        break;
      }
    }
    // A photo that is still downloading or decoding (cached_network_image
    // goes through its database and the file system first) is waited for.
    final bool loadingImages = imageCache.pendingImageCount > 0;
    quiet = pumped <= 4 && !loadingImages ? quiet + 1 : 0;
    if (round >= rounds * 3 && !loadingImages) {
      break;
    }
  }
}

/// Waits for [condition], letting real time and the fake clock advance in
/// turn, then settles.  For work the app hands to another isolate
/// (`compute`), which takes real time that [settle] does not wait for.
Future<void> until(
  WidgetTester tester,
  bool Function() condition, {
  String what = 'condition',
}) async {
  for (var i = 0; i < 600 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!condition()) {
    throw TimeoutException('a11y harness: waited in vain for $what');
  }
  await settle(tester);
}

/// A button of one of the app's dialogs: their labels are in capitals.
Finder dialogButton(String label) => find.text(label.toUpperCase());

/// Text anywhere, including inside rich text.
Finder rich(String text) => find.textContaining(text, findRichText: true);

/// Whether [finder] finds something.
bool present(Finder finder) => finder.evaluate().isNotEmpty;

Future<void> tap(WidgetTester tester, Finder finder) async {
  // The first match that can be hit where it is; failing that, the first
  // match scrolled to the middle of its list (not to its top edge, where a
  // pinned header would cover it).
  Finder target = finder.hitTestable();
  if (!present(finder)) {
    // Not built yet: further down a lazily built list.
    final Finder list = find
        .byWidgetPredicate(
          (Widget w) =>
              w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .hitTestable();
    // From the top: the list may have been left scrolled past the target.
    for (var i = 0; i < 6 && !present(finder) && present(list); i++) {
      await tester.drag(list.first, const Offset(0, 600));
      await tester.pump();
      await settle(tester, rounds: 1);
    }
    for (var i = 0; i < 25 && !present(finder) && present(list); i++) {
      await tester.drag(list.first, const Offset(0, -250));
      await tester.pump();
      await settle(tester, rounds: 1);
    }
  }
  if (!present(target)) {
    await Scrollable.ensureVisible(
      finder.evaluate().first,
      alignment: 0.5,
    );
    await tester.pump();
    await settle(tester, rounds: 1);
    target = present(finder.hitTestable()) ? finder.hitTestable() : finder;
  }
  await tester.tap(target.first);
  await tester.pump();
  await settle(tester);
}

/// Taps [finder] and waits for [expected] to show up: for taps whose
/// handler reads the database or decodes in another isolate before it
/// changes the screen.
Future<void> tapUntil(
  WidgetTester tester,
  Finder finder,
  Finder expected,
) async {
  await tap(tester, finder);
  await until(tester, () => present(expected), what: '$expected');
}

/// Taps the control a screen reader announces as [label], when there is
/// one.  For buttons whose text the app paints itself (`AutoSizeText`),
/// which text finders do not see.  Returns whether it was there.
Future<bool> tapLabelled(WidgetTester tester, String label) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pump();
  try {
    final Finder finder = find.bySemanticsLabel(label);
    if (!present(finder)) {
      // Perhaps scrolled away: back to the top of the page.
      final Finder list = find
          .byWidgetPredicate(
            (Widget w) =>
                w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .hitTestable();
      for (var i = 0; i < 6 && !present(finder) && present(list); i++) {
        await tester.drag(list.first, const Offset(0, 600));
        await tester.pump();
        await settle(tester, rounds: 1);
      }
    }
    if (!present(finder)) {
      return false;
    }
    await tap(tester, finder);
    return true;
  } finally {
    handle.dispose();
  }
}

/// Taps without scrolling the target into view first.
Future<void> tapAt(WidgetTester tester, Finder finder) async {
  await tester.tap(finder.first);
  await tester.pump();
  await settle(tester);
}

Future<void> longPress(WidgetTester tester, Finder finder) async {
  await tester.longPress(finder.first);
  await tester.pump();
  await settle(tester);
}

/// The system back gesture or button.
Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await settle(tester);
}

/// Audits the screen and records what the harness knows about it.
Future<void> shot(
  WidgetTester tester,
  String screenId, {
  bool grow = false,
}) async {
  // What happened between the previous screen and this one belongs to
  // leaving the previous one, unless this is the first screen of a part.
  final int riveGaps = Smooth.takeRiveGaps();
  Smooth.lastScreen = screenId;
  final List<String> exceptions = <String>[
    ...Smooth.takeErrors(tester),
    if (riveGaps > 0)
      'a11y harness: $riveGaps Rive animation build(s) not drawn '
          '(no native Rive renderer under flutter test)',
  ];
  if (Platform.environment['A11Y_WALK_ONLY'] == '1') {
    // ignore: avoid_print
    exceptions.forEach((String e) => print('a11y   ! $e'));
  }
  await maybeDump(tester, screenId);
  await audit(
    tester,
    screenId,
    grow: grow,
    exceptionsSoFar: exceptions,
    takeErrors: () => Smooth.takeErrors(tester),
  );
  Smooth.takeRiveGaps();
  if (grow) {
    usePhoneViewNow(tester);
    await tester.pump();
  }
}

/// With `A11Y_SCREENSHOT_DIR` set, writes the visible text of the screen next
/// to its screenshot.  For finding one's way while writing a walk.
Future<void> maybeDump(WidgetTester tester, String screenId) async {
  final String? dir = Platform.environment['A11Y_SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) {
    return;
  }
  final StringBuffer buffer = StringBuffer();
  for (final Element element
      in find
          .byWidgetPredicate(
            (Widget w) => w is Text || w is Tooltip || w is EditableText,
          )
          .evaluate()) {
    final Widget widget = element.widget;
    buffer.writeln(switch (widget) {
      Text() => 'T ${widget.data ?? widget.textSpan?.toPlainText()}',
      Tooltip() => 'tooltip ${widget.message}',
      EditableText() => 'field ${widget.controller.text}',
      _ => '',
    });
  }
  buffer.writeln('--- tappable (semantics)');
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pump();
  void visit(SemanticsNode node) {
    final SemanticsData data = node.getSemanticsData();
    if (data.hasAction(SemanticsAction.tap) && !node.isInvisible) {
      final Rect r = MatrixUtils.transformRect(
        _toRoot(node),
        node.rect,
      );
      buffer.writeln(
        'S [${data.label.replaceAll('\n', ' | ')}] tip[${data.tooltip}] '
        'val[${data.value}] @${(r.left / 3).round()},${(r.top / 3).round()} '
        '${(r.width / 3).round()}x${(r.height / 3).round()}',
      );
    }
    node.visitChildren((SemanticsNode child) {
      visit(child);
      return true;
    });
  }

  final SemanticsNode? root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (root != null) {
    visit(root);
  }
  handle.dispose();
  buffer.writeln('--- requests');
  Smooth.servers.log.forEach(buffer.writeln);
  buffer.writeln('--- unanswered');
  Smooth.servers.unanswered.forEach(buffer.writeln);
  buffer.writeln('--- channels');
  Smooth.channels.calls.toSet().forEach(buffer.writeln);
  File('$dir/${screenId.replaceAll('/', '__')}.txt')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(buffer.toString());
}

Matrix4 _toRoot(SemanticsNode node) {
  Matrix4 result = Matrix4.identity();
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    if (n.transform != null) {
      result = n.transform!.multiplied(result);
    }
  }
  return result;
}

/// Decodes a JSON asset of the app.
Object? assetJson(String path) => jsonDecode(File(path).readAsStringSync());
