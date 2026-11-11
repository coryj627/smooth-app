// Accessibility audit, part 4 of 6: the product page, its tabs, and the
// pages and sheets it opens.  See README.md in this directory.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/cards/product_cards/smooth_product_image.dart';

import 'support/app.dart';
import 'support/fixtures.dart';

const String _complete = 'A good product for you';
const String _sparse = 'Chili crisp';

/// Opens the product called [name] from the history list.
Future<void> openProduct(WidgetTester tester, String name) async {
  await tap(tester, find.text(l10n.list_navbar_label));
  await tapUntil(
    tester,
    find.text(name),
    find.text(l10n.product_page_tab_for_me),
  );
}

/// Opens a page from the current one, audits it, and comes back.
Future<void> visit(
  WidgetTester tester,
  Finder opener,
  String screenId, {
  bool grow = true,
}) async {
  await tap(tester, opener);
  await shot(tester, screenId, grow: grow);
  await tap(tester, find.byTooltip('Back').last);
}

void main() {
  walk(
    'product',
    const Start(
      history: <String>[kSparse, kComplete],
      userLists: <String, List<String>>{
        'Breakfast': <String>[kMuesli, kOatDrink],
        'To try': <String>[],
      },
    ),
    <String, Part>{
      'tabs': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await shot(tester, 'product/for-me', grow: true);
        await tap(tester, find.text('Health'));
        await shot(tester, 'product/health', grow: true);
        await tap(tester, find.text('Environment'));
        await shot(tester, 'product/environment', grow: true);
        await tap(tester, find.text('Prices'));
        await shot(tester, 'product/prices', grow: true);
        await tap(tester, find.text('Folksonomy'));
        await shot(tester, 'product/folksonomy', grow: true);
      },
      'health panels': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tap(tester, find.text('Health'));
        await visit(
          tester,
          find.text('Nutri-Score A'),
          'product/panel-nutri-score',
        );
        await visit(
          tester,
          find.text('Nutrition facts'),
          'product/panel-nutrition-facts',
        );
        await visit(
          tester,
          find.text('7 ingredients'),
          'product/panel-ingredients',
        );
        await visit(tester, find.text('Processed foods'), 'product/panel-nova');
        await visit(
          tester,
          find.text(l10n.learnMore),
          'product/panel-health-card',
        );

        // A nutrient level opens a sheet, not a page.
        await tap(tester, find.text('Fat'));
        await shot(tester, 'product/nutrient-level-sheet');
        await tap(tester, find.byTooltip('Close'));
      },
      'environment panels': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tap(tester, find.text('Environment'));
        await visit(
          tester,
          find.text('Green-Score A+'),
          'product/panel-green-score',
        );
        await visit(
          tester,
          find.text(l10n.learnMore),
          'product/panel-environment-card',
        );
      },
      'photos': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tap(tester, find.byType(ProductPicture));
        await shot(tester, 'product/photos', grow: true);
        await tap(tester, find.byTooltip('Use this picture as…'));
        await shot(tester, 'product/photos-use-as-menu');
      },
      'questions': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tap(tester, rich(l10n.tap_to_answer));
        await shot(tester, 'product/questions');
        await tap(tester, find.byTooltip('Close'));
      },
      'footer': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tap(tester, find.text('Add to list'));
        await shot(tester, 'product/add-to-list-sheet');
        await tap(tester, find.byTooltip('Close'));

        // The end of the row of actions.
        for (
          var i = 0;
          i < 6 && !present(find.byTooltip('Reorder or hide actions'));
          i++
        ) {
          await tester.drag(find.text('Add to list'), const Offset(-300, 0));
          await settle(tester, rounds: 1);
        }
        await shot(tester, 'product/footer-scrolled');
        await tap(tester, find.byTooltip('Reorder or hide actions'));
        await shot(tester, 'product/footer-settings');
      },
      'alternatives': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tapUntil(
          tester,
          find.text('Compare'),
          find.textContaining('Hazelnut spread'),
        );
        await shot(tester, 'product/alternatives', grow: true);
      },
      'prices': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tap(tester, find.text('Prices'));
        await tap(tester, find.text('View the prices'));
        await shot(tester, 'prices/product-prices');
      },
      'sparse product': (WidgetTester tester) async {
        await openProduct(tester, _sparse);
        await shot(tester, 'product-sparse/for-me', grow: true);
        for (final String tab in <String>[
          'Health',
          'Environment',
          'Prices',
          'Folksonomy',
        ]) {
          if (!present(find.text(tab))) {
            continue;
          }
          await tap(tester, find.text(tab));
          await shot(tester, 'product-sparse/${tab.toLowerCase()}', grow: true);
        }
      },
      'food preferences': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        // The compatibility score leads to the food preferences.
        await tap(tester, find.byTooltip('Your compatibility score: 84%'));
        await shot(tester, 'product/food-preferences', grow: true);
      },
      'edit while signed out': (WidgetTester tester) async {
        await openProduct(tester, _complete);
        await tapUntil(tester, find.text('Edit'), find.text('Edit product'));
        await tapUntil(
          tester,
          find.text('Nutrition facts'),
          find.byType(AlertDialog),
        );
        await shot(tester, 'edit/sign-in-required-dialog');
      },
      'offline': (WidgetTester tester) async {
        Smooth.servers.offline = true;
        await openProduct(tester, _complete);
        await shot(tester, 'product/offline');
        Smooth.servers.offline = false;
      },
    },
  );
}
