// Accessibility audit, part 3 of 6: the lists tab (history, the user's own
// lists, their menus and dialogs).  See README.md in this directory.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/fixtures.dart';

const Start _someLists = Start(
  history: kListBarcodes,
  userLists: <String, List<String>>{
    'Breakfast': <String>[kMuesli, kOatDrink],
    'To try': <String>[],
  },
);

Future<void> openLists(WidgetTester tester) =>
    tap(tester, find.text(l10n.list_navbar_label));

/// Opens the sheet that lists the lists.
///
/// An open one is closed first: the audit's 320 px pass changes the size of
/// the screen, which leaves the sheet shrunk to its header.
Future<void> openChooser(WidgetTester tester) async {
  await settle(tester, rounds: 1);
  if (present(find.text(l10n.product_list_select))) {
    await back(tester);
  }
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pump();
  await tapUntil(
    tester,
    find.bySemanticsLabel(l10n.action_change_list),
    // The last entry of the sheet: its list is read from the database.
    find.text('Scan history'),
  );
  handle.dispose();
}

void main() {
  walk('lists', _someLists, <String, Part>{
    'history': (WidgetTester tester) async {
      await openLists(tester);
      await shot(tester, 'lists/history', grow: true);

      await tap(tester, find.byTooltip('Show menu'));
      await shot(tester, 'lists/history-menu');
      await tap(tester, find.text(l10n.clear_long));
      await shot(tester, 'lists/history-clear-confirm');
      await tap(tester, dialogButton(l10n.no));

      await tap(tester, find.text(l10n.user_lists_action_multi_select));
      await shot(tester, 'lists/multi-select');
      await tap(tester, find.textContaining('Oat drink'));
      await tap(tester, find.textContaining('Coca-Cola Original'));
      await shot(tester, 'lists/multi-select-two-selected');
      await tap(tester, find.byTooltip('Show menu'));
      await shot(tester, 'lists/multi-select-menu');
      await back(tester);
      await tap(tester, find.byTooltip('Close'));
    },
    'list chooser': (WidgetTester tester) async {
      await openLists(tester);
      await openChooser(tester);
      await shot(tester, 'lists/chooser');

      await openChooser(tester);
      await tap(tester, find.text(l10n.product_list_create));
      await shot(tester, 'lists/create-dialog');
      await tap(tester, dialogButton(l10n.cancel));

      await openChooser(tester);
      await tap(tester, find.text('Breakfast'));
      await shot(tester, 'lists/user-list');
      await tap(tester, find.byTooltip('Show menu'));
      await shot(tester, 'lists/user-list-menu');
      await tap(tester, find.text(l10n.user_list_popup_rename));
      await shot(tester, 'lists/rename-dialog');
      await tap(tester, dialogButton(l10n.cancel));

      await openChooser(tester);
      await tap(tester, find.text('To try'));
      await shot(tester, 'lists/user-list-empty');
    },
    'empty history': (WidgetTester tester) async {
      await Smooth.device(tester, const Start());
      await openLists(tester);
      await openChooser(tester);
      await shot(tester, 'lists/chooser-no-user-list');
      await openChooser(tester);
      await tap(tester, find.text('All viewed products'));
      await shot(tester, 'lists/history-empty');
    },
  });
}
