# Runtime accessibility audit (`a11y-dogfood` branch only)

These tests start the real app, walk to its screens the way a user does (taps,
typing, the back button), and run the `flutter_a11y_test` battery on each one.
Findings are **recorded, not asserted**: a test fails only when the walk itself
breaks (a screen can no longer be reached), never because a screen has findings.

```sh
cd packages/smooth_app
flutter pub get            # needs read access to coryj627/flutter-a11y (private)
flutter test test/a11y     # about 45 s; writes the two files below
```

| Output | What |
|---|---|
| `.a11y/flutter/runtime-findings.json` | The findings (`RuntimeFindingsSink`), which `a11y_check_flutter scan` merges into its report. Two runs in a row are byte-identical. |
| `.a11y/flutter/runtime-screens.json` | One entry per screen: view size, findings per rule, how many point into `lib/`, rules that could not run, and the exceptions the framework caught on that screen. |

Aids for working on the walks (not used by CI):

- `A11Y_SCREENSHOT_DIR=/some/dir` writes `<screen id>.png` (what was audited) and
  `<screen id>.txt` (visible text, tappable semantics nodes, requests made).
- `A11Y_WALK_ONLY=1` walks without auditing; `A11Y_ONLY="part,part"` runs only
  those parts of a file.
- `A11Y_TEST_FONT=ahem` skips the real fonts.

## Layout

| File | What it walks |
|---|---|
| `screens_onboarding_a11y_test.dart` | A first run: the six onboarding pages, then the scan tab without camera permission. |
| `screens_scan_a11y_test.dart` | The scan tab in each state of a scanned barcode, and the search. |
| `screens_lists_a11y_test.dart` | The lists tab: history, the user's lists, menus and dialogs. |
| `screens_product_a11y_test.dart` | The product page, its tabs, knowledge panels, photos, sheets. |
| `screens_edit_a11y_test.dart` | Signed in: every edit page, add a price, the new-product form. |
| `screens_preferences_a11y_test.dart` | The profile tab, every preferences page, sign-in and sign-up. |
| `screens_no_camera_a11y_test.dart` | The scan tab on a device with no camera. |
| `support/app.dart` | Starts the app, drives it (`tap`, `until`, `shot`), keeps the walk going. |
| `support/fake_backend.dart` | Stand-ins for the servers, image downloads and plugins. |
| `support/fixtures.dart` | The products and the servers' answers. |
| `support/harness.dart` | Fonts, viewport, growing the view, the audit call, the screen log. |
| `flutter_test_config.dart` | The findings sink and fonts, for this directory only. The app has no `test/flutter_test_config.dart`, so its other tests are untouched. |

There is one test per file, made of named parts, because **the app can be
started once per process**: `launchSmoothApp` sets a `late final`, and the
widget tree disposes the app's static `UserPreferences` and `LocalDatabase`
when it is taken down. A part that throws is logged as `part:<name>` with
status `failed`, the walk goes back to the first page and continues, and the
test fails at the end. `flutter test` runs the seven files in parallel.

## Screens audited (115)

| Prefix | Count | Screens |
|---|---|---|
| `onboarding/` | 8 | `home`, `country`, `country-picker`, `health-card`, `health-card-nutriscore`, `eco-card`, `preferences`, `permissions` |
| `scan/` | 8 | `empty`, `camera-permission-denied`, `no-camera`, `product-loading`, `product-found`, `product-found-sparse`, `product-unknown`, `product-error` |
| `search/` | 5 | `history`, `results`, `personalised-ranking`, `no-result`, `error` |
| `lists/` | 14 | `history`, `history-empty`, `history-menu`, `history-clear-confirm`, `multi-select`, `multi-select-two-selected`, `multi-select-menu`, `chooser`, `chooser-no-user-list`, `create-dialog`, `rename-dialog`, `user-list`, `user-list-empty`, `user-list-menu` |
| `product/` | 22 | `for-me`, `health`, `environment`, `prices`, `folksonomy`, `panel-nutri-score`, `panel-nutrition-facts`, `panel-ingredients`, `panel-nova`, `panel-health-card`, `panel-green-score`, `panel-environment-card`, `nutrient-level-sheet`, `photos`, `photos-use-as-menu`, `questions`, `add-to-list-sheet`, `footer-scrolled`, `footer-settings`, `alternatives`, `food-preferences`, `offline` |
| `product-sparse/` | 3 | `for-me`, `prices`, `folksonomy` |
| `edit/` | 21 | `menu`, `sign-in-required-dialog`, `basic-details`, `ingredients`, `nutrition-facts`, `packaging`, `packaging-photo`, `additional-details`, `categories`, `categories-suggestions`, `leave-with-changes-dialog`, `labels`, `traces`, `stores`, `origins`, `traceability-codes`, `countries`, `photos`, `folksonomy`, `barcode-sheet`, `help-sheet` |
| `new-product/` | 6 | `product-type`, `step-photos`, `step-nutri-score`, `step-green-score`, `step-nova`, `step-basic-details` |
| `prices/` | 3 | `home`, `product-prices`, `add-price` |
| `preferences/` | 17 | `profile-signed-out`, `profile-signed-in`, `search-results`, `food`, `app-settings`, `app-settings-theme`, `app-settings-language`, `app-settings-country`, `app-settings-currency`, `app-settings-image-source`, `contribute`, `contributions`, `faq`, `connect`, `about`, `legal`, `licenses` |
| `account/` | 6 | `login`, `login-empty-fields`, `login-wrong-password`, `forgot-password`, `sign-up`, `manage` |
| `donation/`, `hunger-games/` | 2 | `donation/page`, `hunger-games/questions` |

All in English, light theme, 412x915 logical px at device pixel ratio 3.

## Not audited, and why

- **The camera preview and the live scanner.** No camera under `flutter test`.
  The app's own `MockedScanner` (its development entry point) stands in: the
  camera area is empty. A scan is `ContinuousScanModel.onScan(barcode)`, the
  call the scanner makes on a detection.
- **The scan header ("Clear", "Compare N products") and the compare page from
  it.** With the mocked scanner the header is not on screen; a tap on it does
  nothing.
- **Rive animations** (the onboarding sun, the loading and error animations on
  scan cards, the search eye). They need the native Rive renderer, which
  `flutter test` only has after `dart run rive_native:setup`, a download. Each
  one is an empty box of the animation's size, and the screen's log entry says
  how many.
- **Dark and AMOLED themes, other languages, tablets.**
- **Pages behind a system or external UI**: the photo picker and cropper, the
  share sheet, web pages (terms of use, the FAQ articles, donations checkout),
  the e-mail composer, the app-store review prompt.
- **Photo viewer with zoom, OCR extraction, sending a price, saving an edit,
  deleting an account.** Reachable only by writing to the server or picking a
  file; the walks stop before the step that sends.
- **The new-product form past empty steps**, the sub-pages of the prices home
  (contributors, stores, proofs, statistics, challenges), the guides
  (Nutri-Score, NOVA, Green-Score and the "Discover" pages), the product
  loader page of a deep link, dev mode, and the cosmetics, pet food and other
  product types (pages, preferences). Not reached for lack of time or of
  server answers to build them from; nothing in the app prevents it.
- **The news feed card of the scan tab.** Its JSON is not served (404), so the
  app shows its built-in tagline.
- **Long pickers** (countries, languages, currencies) are audited as their
  first viewport only.

## Decisions that affect findings

- **The real app.** `launchSmoothApp(screenshots: true)`, the app's own mode
  for tests: no analytics or crash reports, no native splash, no debug banner.
  Two things that mode leaves undone are done by the harness, as the app's own
  widget tests do: Matomo is initialised opted-out (`mockMatomo` in
  `test/tests_utils/mocks.dart`; without it every page that reports a page view
  throws while building), and `UserPreferences.init` sets the default food
  preference importances.
- **Real fonts.** OpenSans and the two icon fonts from `pubspec.yaml`, Roboto
  and MaterialIcons from the Flutter SDK. Two gaps remain: text the app paints
  with no font family at all (the compatibility gauge and the
  "Importance / Matches" switch of the "For me" tab) is drawn in the test
  font, as blocks, where a device uses its system font; and emoji (the flags of
  the country picker) are not drawn.
- **Viewport** 412x915 at DPR 3. Screens audited with `grow` are made taller
  until nothing is left to scroll (at most 6000 px), so a lazy list is audited
  whole; a collapsing header cannot be grown away and is left as it is.
- **Audit configuration**: library defaults, both platform tap-target
  guidelines (`platform: null`), reflow on, `sourceRoots` = `lib/`.
- **Attribution never lands in `lib/generic_lib/animations/rive_animation.dart`.**
  With no Rive renderer the app's `Provider<FileLoader>` fails to create its
  value, and provider then throws from `debugFillProperties`, which the audit
  calls on every project widget above a finding. That one file is declared
  "not project code" to the widget inspector so the audit steps over it.
- **When the audit's own re-layout makes the app throw.** With flutter-a11y
  0.4.1 (the version pinned here) a reflow pass during which the app raises
  anything other than an overflow is aborted and contributes no finding; the
  other passes and every other phase keep theirs, and `auditScreen` throws
  `A11yReflowException` with that result, which the harness keeps as the
  screen's (the result carries a `reflow-pass-aborted` diagnostic).
  `rulesNotRun` in the screen log names the rules whose pass did not complete:
  the aborted ones, plus the 320 px pass when the library stopped because the
  view could not be put back after the scale pass. `exceptions` has one
  `reflow pass aborted (<pass>): <error>` line per failure the library
  reports. Any other error from the audit is handled as with 0.4.0: the screen
  is audited again without the reflow passes, and the log says so. Today: six
  edit screens without the 320 px pass
  (`_AutoScaleRenderObject does not meet its constraints`,
  `lib/widgets/auto_scale_widget.dart`), and `prices/product-prices` without
  either pass (a framework semantics assertion on every frame once semantics
  are on: the scale pass aborts, putting the view back raises it again, and
  the 320 px pass is not attempted; that screen has 2 findings and is in
  effect not audited).
- **Exceptions are evidence.** Framework-caught errors and errors nobody
  catches are listed on the screen they happened on (`exceptions`,
  `exceptionsWhileLeaving`), not hidden and not fatal.
- **Offstage tabs are in the tree.** The three tabs live in an `IndexedStack`,
  and the audit's overflow detection also measures the two that are not shown.
  The same three sites (`scan_header.dart:64` and `:87`,
  `profile_app_bar.dart:133`) are therefore reported on almost every screen:
  521 of the 613 overflow findings.
- **Sheets and the 320 px pass.** A draggable sheet shrinks to its header when
  the screen size changes, so the reflow pass of a sheet measures it shrunk.

## What is faked

Nothing leaves the machine. `package:http` goes to a `MockClient`
(`http.runWithClient`), `NetworkImage` to a fake `HttpClient`.

| Real thing | Stand-in |
|---|---|
| Product API | `assets/onboarding/sample_product_data.json`, the app's own sample of a real server response, completed with the fields today's app asks for (names per language, `images`, packagings, countries, stores...). Four more products are that response with name, brand, quantity and scores changed (list rows only). A sparse product has a name and one photo. |
| Simplified knowledge panels | The server now sends `simplified_root` and two `*_simplified` cards, which the product page builds its Health and Environment tabs from; the sample predates them. They are assembled from the sample's own panels in the shape the app's `test/knowledge_panel/simplified_health_card_test.dart` describes. |
| Preferences and attribute groups | The copies in `assets/metadata/`. |
| Search | Always the five complete products; nothing for one reserved term. |
| Open Prices, Folksonomy, Robotoff | Three prices, two properties and one question for the complete product, written for this harness. |
| Sign-in | One account. |
| Ordered nutrients (`/cgi/nutrients.pl`) | A label-order list of 18 nutrients written for this harness; the app ships no copy. |
| Taxonomy suggestions | A few entries per taxonomy. |
| Product photos | One drawn picture of a jar (`support/product_photo.png`). Text over a photo is measured against it. |
| Score and label pictograms | The app's `assets/cache` and `assets/cacheTintable` by file name; a grey square for the ones not shipped. |
| Map tiles | One drawn tile. |
| Database | The real one (sqflite through `sqflite_common_ffi`, Hive) in a scratch directory per process. |
| Plugins | `path_provider` (scratch directory), `shared_preferences` and `flutter_secure_storage` (their own in-memory mocks), `permission_handler`, `package_info_plus`, `connectivity_plus`, `url_launcher` and others answered on their method channels. |

## CI

`.github/workflows/a11y-check-flutter.yml` (repository root) runs this
directory and then `a11y_check_flutter scan` in `packages/smooth_app`, with
`.a11y/a11y-check-flutter.yaml`. Nothing has been pushed and no baseline has
been accepted. SARIF paths are relative to `packages/smooth_app`; set the
action's `repo-root` if code scanning should resolve them from the repository
root.
