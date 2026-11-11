// Accessibility audit, part 5 of 6: editing a product, adding a price and
// adding a new product, as a signed-in contributor.  See README.md in this
// directory.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/data_models/continuous_scan_model.dart';

import 'support/app.dart';
import 'support/fixtures.dart';

/// Opens the "Edit product" page of the complete product.
Future<void> openEdit(WidgetTester tester) async {
  await tap(tester, find.text(l10n.list_navbar_label));
  await tapUntil(
    tester,
    find.text('A good product for you'),
    find.text(l10n.product_page_tab_for_me),
  );
  await tapUntil(tester, find.text('Edit'), find.text('Edit product'));
}

/// Opens the entry called [entry] of the "Edit product" page, audits the
/// page it leads to, and comes back.
Future<void> editPage(
  WidgetTester tester,
  String entry,
  String screenId,
) async {
  await tap(tester, find.text(entry));
  await until(
    tester,
    () => !present(find.text('Edit product')),
    what: 'the page behind "$entry"',
  );
  await shot(tester, screenId, grow: true);
  await tap(tester, find.byTooltip('Back').last);
  await until(
    tester,
    () => present(find.text('Edit product')),
    what: 'the edit page after "$entry"',
  );
}

void main() {
  walk(
    'edit',
    const Start(history: <String>[kSparse, kComplete], signedIn: true),
    <String, Part>{
      'edit page': (WidgetTester tester) async {
        await openEdit(tester);
        await shot(tester, 'edit/menu', grow: true);
      },
      'details': (WidgetTester tester) async {
        await openEdit(tester);
        await editPage(tester, 'Basic details', 'edit/basic-details');
        await editPage(tester, 'Ingredients', 'edit/ingredients');
        await editPage(tester, 'Nutrition facts', 'edit/nutrition-facts');
        await editPage(tester, 'Packaging components', 'edit/packaging');
        await editPage(
          tester,
          'Recycling instructions photo',
          'edit/packaging-photo',
        );
        await editPage(tester, 'Additional details', 'edit/additional-details');
      },
      'lists of values': (WidgetTester tester) async {
        await openEdit(tester);
        await editPage(tester, 'Categories', 'edit/categories');
        await editPage(tester, 'Labels & Certifications', 'edit/labels');
        await editPage(tester, 'Traces', 'edit/traces');
        await editPage(tester, 'Stores', 'edit/stores');
        await editPage(tester, 'Origins', 'edit/origins');
        await editPage(tester, 'Traceability codes', 'edit/traceability-codes');
        await editPage(tester, 'Country', 'edit/countries');
      },
      'typing in an edit page': (WidgetTester tester) async {
        await openEdit(tester);
        await tap(tester, find.text('Categories'));
        await until(tester, () => !present(find.text('Edit product')));
        await tester.enterText(find.byType(TextField).first, 'sou');
        await settle(tester);
        await shot(tester, 'edit/categories-suggestions');
        // Leaving with something typed: the app asks what to do with it.
        await tap(tester, find.byTooltip('Back').last);
        await shot(tester, 'edit/leave-with-changes-dialog');
      },
      'photos': (WidgetTester tester) async {
        await openEdit(tester);
        await editPage(tester, 'Photos', 'edit/photos');
      },
      'folksonomy': (WidgetTester tester) async {
        await openEdit(tester);
        await editPage(tester, 'Folksonomy', 'edit/folksonomy');
      },
      'add a price': (WidgetTester tester) async {
        await openEdit(tester);
        await tap(tester, find.text('Add a price'));
        await until(tester, () => !present(find.text('Edit product')));
        await shot(tester, 'prices/add-price', grow: true);
      },
      'edit page footer': (WidgetTester tester) async {
        await openEdit(tester);
        await tap(tester, find.text('View barcode'));
        await shot(tester, 'edit/barcode-sheet');
        await Smooth.home(tester);
        await openEdit(tester);
        await tap(tester, find.text('Help'));
        await shot(tester, 'edit/help-sheet');
      },
      'new product': (WidgetTester tester) async {
        final ContinuousScanModel model = Smooth.read<ContinuousScanModel>(
          tester,
        );
        await real(tester, () => model.onScan(kUnknown));
        await until(
          tester,
          () => present(find.text(l10n.carousel_unknown_product_button)),
          what: 'the unknown product card',
        );
        await tap(tester, find.text(l10n.carousel_unknown_product_button));
        await shot(tester, 'new-product/product-type');
        await tap(tester, find.text('Food'));
        // The steps of the form, as far as "Next" goes with nothing filled in.
        for (final String step in <String>[
          'photos',
          'nutri-score',
          'green-score',
          'nova',
          'basic-details',
        ]) {
          if (!await tapLabelled(tester, l10n.next_label)) {
            fail('new product: no "Next" before the $step step');
          }
          await shot(tester, 'new-product/step-$step', grow: true);
        }
      },
    },
  );
}
