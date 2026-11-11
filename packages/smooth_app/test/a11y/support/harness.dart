/// Shared plumbing for the accessibility audit in `screens_a11y_test.dart`:
/// real fonts, the phone viewport, growing the view over lazy lists, the
/// audit call itself, and the per-screen log.
///
/// See `README.md` in this directory for what each decision does to findings.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_a11y_test/flutter_a11y_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone viewport used for every screen (logical px, DPR 3).
const Size kPhoneSize = Size(412, 915);
const double kPhoneDpr = 3;

/// The tallest a view is ever grown to (logical px).
///
/// The contrast rules rasterize the whole view at [kPhoneDpr]; this keeps
/// that image under about 100 MB.
const double kMaxGrownHeight = 6000;

/// Where the per-screen log goes, next to the findings the sink writes.
const String kScreensLogPath = '.a11y/flutter/runtime-screens.json';

/// The audit configuration for every screen.
///
/// Library defaults, with both platform tap-target guidelines
/// (`platform: null`; the app ships on Android and iOS), the reflow passes on,
/// and attribution restricted to the app's `lib/` so that a finding is never
/// attributed to this harness.
A11yAuditConfig get auditConfig => A11yAuditConfig(
  platform: null,
  reflow: true,
  sourceRoots: ['${Directory.current.path}/lib/'],
);

/// [auditConfig] with every rule but [rules].
A11yAuditConfig _without(Set<String> rules) => A11yAuditConfig(
  platform: null,
  reflow: true,
  sourceRoots: ['${Directory.current.path}/lib/'],
  rules: {
    for (final rule in listRuntimeRules())
      if (!rules.contains(rule.id)) rule.id,
  },
);

/// Tells Flutter's widget inspector that every file under `lib/` is project
/// code except [files] (paths relative to the package).
///
/// The audit asks the inspector for the creation location of each project
/// widget above a finding, which serializes the widget's diagnostics.  A
/// widget whose diagnostics throw would end the audit; leaving its file out
/// makes the audit step over it.  Findings are then never attributed to
/// [files], but to the nearest project widget above.
void attributeToLibExcept(List<String> files) {
  final root = Directory.current.path;
  final excluded = {for (final f in files) '$root/$f'};
  final roots = <String>[];
  void visit(Directory dir) {
    for (final entity in dir.listSync()) {
      if (excluded.contains(entity.path)) continue;
      if (entity is Directory &&
          excluded.any((e) => e.startsWith('${entity.path}/'))) {
        visit(entity);
      } else {
        roots.add(entity is Directory ? '${entity.path}/' : entity.path);
      }
    }
  }

  visit(Directory('$root/lib'));
  // ignore: invalid_use_of_protected_member
  WidgetInspectorService.instance.addPubRootDirectories(roots);
}

/// Loads the fonts the app ships, plus the two Material fonts from the
/// Flutter SDK, so text is measured as on a device rather than in the
/// `FlutterTest` font (every glyph a 1 em square).
///
/// Set `A11Y_TEST_FONT=ahem` to skip this and compare with the default font.
Future<void> loadRealFonts() async {
  if (Platform.environment['A11Y_TEST_FONT'] == 'ahem') return;

  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        throw StateError('a11y harness: font file missing: $path');
      }
      loader.addFont(
        file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  }

  // The families declared under `flutter: fonts:` in pubspec.yaml.
  final pubspecFonts = _pubspecFonts();
  for (final MapEntry(key: family, value: assets) in pubspecFonts.entries) {
    await load(family, assets);
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('a11y harness: FLUTTER_ROOT is not set');
  }
  final materialFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await load('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);
  await load('Roboto', [
    for (final style in ['Regular', 'Italic', 'Medium', 'Bold'])
      '$materialFonts/Roboto-$style.ttf',
  ]);
}

/// Family name to asset paths, read from the `fonts:` section of pubspec.yaml.
///
/// A small line-based reader, to avoid a YAML dependency: the section is a
/// list of `- family: X` entries each followed by `- asset: path` lines.
Map<String, List<String>> _pubspecFonts() {
  final result = <String, List<String>>{};
  String? family;
  var inFonts = false;
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    if (line == '  fonts:') {
      inFonts = true;
      continue;
    }
    if (!inFonts) continue;
    final familyMatch = RegExp(r'^\s+- family:\s*(.+?)\s*$').firstMatch(line);
    if (familyMatch != null) {
      family = familyMatch.group(1)!;
      result[family] = [];
      continue;
    }
    final assetMatch = RegExp(r'^\s+- asset:\s*(.+?)\s*$').firstMatch(line);
    if (assetMatch != null && family != null) {
      result[family]!.add(assetMatch.group(1)!);
    }
  }
  if (result.isEmpty) {
    throw StateError('a11y harness: no fonts found in pubspec.yaml');
  }
  return result;
}

/// Sets the phone viewport on the view (not just the surface), so
/// `MediaQuery` and the audit's reflow pass both start from it.
void usePhoneView(WidgetTester tester, {Size size = kPhoneSize}) {
  usePhoneViewNow(tester, size: size);
  addTearDown(tester.view.reset);
}

/// Puts the view back to the phone viewport, after [growViewToFit].
void usePhoneViewNow(WidgetTester tester, {Size size = kPhoneSize}) {
  tester.view.devicePixelRatio = kPhoneDpr;
  tester.view.physicalSize = size * kPhoneDpr;
}

/// How far the vertical scrollables on screen can still scroll, in total.
double remainingScrollPx(WidgetTester tester) {
  var total = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final position = (element as StatefulElement).state as ScrollableState;
    final p = position.position;
    if (!p.hasContentDimensions || p.axis != Axis.vertical) continue;
    total += p.maxScrollExtent - p.minScrollExtent;
  }
  return total;
}

/// Grows the view's height until no vertical scrollable has anything left to
/// scroll, so a lazily built list is laid out (and audited) in full.
///
/// Stops at [kMaxGrownHeight].  Returns the final logical size.
Future<Size> growViewToFit(WidgetTester tester) async {
  var size = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var i = 0; i < 12; i++) {
    final remaining = remainingScrollPx(tester);
    if (remaining <= 0.5 || size.height >= kMaxGrownHeight) break;
    final before = size;
    size = Size(
      size.width,
      (size.height + remaining).ceilToDouble().clamp(0, kMaxGrownHeight),
    );
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // A scrollable whose extent does not depend on the height of the view
    // (a header that collapses as the page scrolls) cannot be grown away:
    // growing further would only add empty space.
    if (remainingScrollPx(tester) >= remaining - 0.5) {
      size = before;
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      break;
    }
  }
  return size;
}

/// [messages] with each repeated message once, prefixed by its count.
List<String> countRepeats(List<String> messages) {
  final counts = <String, int>{};
  for (final message in messages) {
    counts[message] = (counts[message] ?? 0) + 1;
  }
  return [
    for (final MapEntry(key: message, value: count) in counts.entries)
      count == 1 ? message : '$count x $message',
  ];
}

/// Takes every exception the framework has caught since the last call.
///
/// [WidgetTester.takeException] returns only the first one; later ones are
/// only printed.  One is enough to say that the pump was not clean.
List<String> takeExceptions(WidgetTester tester) {
  final result = <String>[];
  while (true) {
    final Object? exception = tester.takeException();
    if (exception == null) break;
    result.add(describeException(exception));
  }
  return result;
}

/// The first line of an exception, without memory addresses or hash codes.
String describeException(Object exception) {
  final text = exception is FlutterError
      ? exception.toStringShort() == 'FlutterError'
            ? exception.message
            : exception.toString()
      : exception.toString();
  final firstLine = text
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => text);
  return '${exception.runtimeType}: '
      '${firstLine.replaceAll(RegExp(r'#[0-9a-f]{5}\b'), '#…')}';
}

/// Per-isolate log of the screens this run audited, merged into
/// [kScreensLogPath] by [flush].
abstract final class ScreenLog {
  static final Map<String, Map<String, Object>> _screens = {};

  static void audited(
    String screenId,
    A11yAuditResult result, {
    required Size viewSize,
    required double remainingScroll,
    required List<String> exceptions,
    List<String> rulesNotRun = const [],
  }) {
    final perRule = <String, int>{};
    var inLib = 0;
    for (final finding in result.findings) {
      perRule[finding.ruleID] = (perRule[finding.ruleID] ?? 0) + 1;
      if (finding.filePath.startsWith('lib/') ||
          finding.filePath.contains('/lib/')) {
        inLib++;
      }
    }
    _screens[screenId] = <String, Object>{
      'status': 'audited',
      'viewSize': '${viewSize.width.round()}x${viewSize.height.round()}',
      'remainingScrollPx': remainingScroll.round(),
      'findingCount': result.findings.length,
      'findingsInLib': inLib,
      'rules': Map.fromEntries(
        perRule.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      if (result.diagnostics.isNotEmpty)
        'diagnostics': [for (final d in result.diagnostics) d.id]..sort(),
      if (rulesNotRun.isNotEmpty) 'rulesNotRun': rulesNotRun,
      if (exceptions.isNotEmpty) 'exceptions': countRepeats(exceptions),
    };
  }

  /// Exceptions the framework caught after [screenId] was audited, while
  /// the walk left it.
  static void exceptionsAfter(String screenId, List<String> exceptions) {
    final screen = _screens[screenId];
    if (screen == null || exceptions.isEmpty) return;
    screen['exceptionsWhileLeaving'] = countRepeats([
      ...?(screen['exceptionsWhileLeaving'] as List<String>?),
      ...exceptions,
    ]);
  }

  /// A screen whose audit threw, or a part of a walk that threw before
  /// reaching its screens.
  static void failed(String id, String error) {
    _screens[id] = <String, Object>{'status': 'failed', 'error': error};
  }

  /// Merges this isolate's screens into [kScreensLogPath].
  ///
  /// Test files run in parallel processes, so the read-modify-write is done
  /// under a lock file.
  static Future<void> flush() async {
    if (_screens.isEmpty) return;
    final file = File(kScreensLogPath);
    file.parent.createSync(recursive: true);
    final lock = File('$kScreensLogPath.lock').openSync(mode: FileMode.write)
      ..lockSync(FileLock.blockingExclusive);
    try {
      _merge(file);
    } finally {
      lock
        ..unlockSync()
        ..closeSync();
    }
  }

  static void _merge(File file) {
    final merged = <String, Object?>{};
    if (file.existsSync()) {
      try {
        merged.addAll(
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
        );
      } on Object {
        // An unreadable log is replaced.
      }
    }
    merged.addAll(_screens);
    final sorted = Map.fromEntries(
      merged.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
    );
  }
}

/// Writes a PNG of the screen to `$A11Y_SCREENSHOT_DIR/<screenId>.png`, when
/// that variable is set.  For checking by eye that a screen was reached and
/// looks as it does in the app; not part of the audit.
Future<void> maybeScreenshot(WidgetTester tester, String screenId) async {
  final dir = Platform.environment['A11Y_SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final renderView = tester.binding.renderViews.first;
  // ignore: invalid_use_of_protected_member
  final layer = renderView.layer! as OffsetLayer;
  final size = tester.view.physicalSize;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & size, pixelRatio: 2 / 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$dir/${screenId.replaceAll('/', '__')}.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Audits the screen as it stands and records the result.
///
/// [grow] lays a lazy list out in full first; see [growViewToFit].
/// Exceptions thrown while the screen was pumped, or during the audit's own
/// re-layouts, are recorded on the screen rather than failing the test:
/// an overflow or a missing plugin is evidence about the screen.
/// [takeErrors] returns the exceptions since its last call; by default the
/// one the test binding holds.
///
/// With `A11Y_WALK_ONLY=1` nothing is audited (for writing a walk).
Future<A11yAuditResult?> audit(
  WidgetTester tester,
  String screenId, {
  bool grow = false,
  List<String> exceptionsSoFar = const [],
  List<String> Function()? takeErrors,
}) async {
  final take = takeErrors ?? () => takeExceptions(tester);
  final exceptions = [...exceptionsSoFar, ...take()];
  var viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  if (grow) {
    viewSize = await growViewToFit(tester);
    exceptions.addAll(take());
  }
  final remaining = remainingScrollPx(tester);
  await maybeScreenshot(tester, screenId);

  if (Platform.environment['A11Y_WALK_ONLY'] == '1') {
    // ignore: avoid_print
    print('a11y $screenId: reached (not audited, A11Y_WALK_ONLY)');
    return null;
  }

  // The audit lays the screen out again at 200 % text and at 320 px wide.
  // If the app throws something other than an overflow while it does, the
  // library aborts that pass (it contributes no finding), runs the others,
  // records the result to the sink and throws `A11yReflowException`.  That
  // result is the screen's; the aborted passes' rules go to `rulesNotRun` and
  // their errors to `exceptions`.  Any other error is handled as before: the
  // screen is audited again without the reflow passes, and the log says so.
  A11yAuditResult? result;
  var rulesNotRun = const <String>[];
  final attempts = <(List<String>, A11yAuditConfig)>[
    (const [], auditConfig),
    (
      const [RuleIds.contentOverflowAtReflowWidth],
      _without({RuleIds.contentOverflowAtReflowWidth}),
    ),
    (
      const [RuleIds.textOverflowAtScale],
      _without({RuleIds.textOverflowAtScale}),
    ),
    (
      const [RuleIds.contentOverflowAtReflowWidth, RuleIds.textOverflowAtScale],
      _without({
        RuleIds.contentOverflowAtReflowWidth,
        RuleIds.textOverflowAtScale,
      }),
    ),
  ];
  for (final (rules, config) in attempts) {
    try {
      result = await auditScreen(tester, screenId: screenId, config: config);
      rulesNotRun = rules;
      break;
    } on A11yReflowException catch (error) {
      result = error.result;
      // `failures` names every pass that did not complete: the aborted ones,
      // and (since 0.4.2) each pass not attempted because the view could not
      // be put back after an earlier one (`ReflowPassNotAttempted`).
      rulesNotRun = {
        ...rules,
        for (final failure in error.failures) failure.ruleId,
      }.toList()..sort();
      for (final failure in error.failures) {
        exceptions.add(
          'reflow pass aborted (${failure.pass}): '
          '${describeException(failure.error)}',
        );
      }
      // Back to the size and text scale the screen was pumped at.
      tester.view.physicalSize = viewSize * tester.view.devicePixelRatio;
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      take();
      break;
    } on Object catch (error) {
      exceptions.add(
        'the audit threw'
        '${rules.isEmpty ? '' : ' (run without ${rules.join(' and ')})'}: '
        '${describeException(error)}',
      );
      // Back to the size and text scale the screen was pumped at.
      tester.view.physicalSize = viewSize * tester.view.devicePixelRatio;
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      take();
    }
  }
  exceptions.addAll([for (final e in take()) 'during the audit: $e']);

  if (result == null) {
    ScreenLog.failed(screenId, exceptions.join('\n'));
    // ignore: avoid_print
    print('a11y $screenId: AUDIT FAILED');
    return null;
  }
  ScreenLog.audited(
    screenId,
    result,
    viewSize: viewSize,
    remainingScroll: remaining,
    exceptions: exceptions,
    rulesNotRun: rulesNotRun,
  );
  // ignore: avoid_print
  print(
    'a11y $screenId: ${result.findings.length} finding(s)'
    '${exceptions.isEmpty ? '' : ', ${exceptions.length} exception(s)'}'
    '${rulesNotRun.isEmpty ? '' : ', without ${rulesNotRun.join(' and ')}'}',
  );
  return result;
}
