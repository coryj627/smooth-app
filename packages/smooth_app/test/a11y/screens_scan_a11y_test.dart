// Accessibility audit, part 2 of 6: the scan tab in each of its states, and
// the search.  See README.md in this directory.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/data_models/continuous_scan_model.dart';
import 'package:smooth_app/pages/personalized_ranking_page.dart';

import 'support/app.dart';
import 'support/fixtures.dart';

/// What the scanner does when the camera reads [barcode].
Future<void> scan(WidgetTester tester, String barcode) async {
  final ContinuousScanModel model = Smooth.read<ContinuousScanModel>(tester);
  await real(tester, () => model.onScan(barcode));
  await settle(tester);
}

/// Types [terms] in the search field and submits.
Future<void> search(WidgetTester tester, String terms) async {
  await tester.enterText(find.byType(TextField).first, terms);
  await settle(tester);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
}

const List<String> _searches = <String>[
  'oat drink',
  'granola',
  '3017620422003',
];

void main() {
  walk(
    'scan and search',
    const Start(searchHistory: _searches),
    <String, Part>{
      'scan': (WidgetTester tester) async {
        await shot(tester, 'scan/empty');

        // The server takes its time: the card of a barcode being looked up.
        Smooth.servers.slow = Completer<void>();
        await scan(tester, kComplete);
        await shot(tester, 'scan/product-loading');
        Smooth.servers.slow!.complete();
        Smooth.servers.slow = null;
        await until(
          tester,
          () => present(find.text('A good product for you')),
          what: 'the scanned product',
        );
        await shot(tester, 'scan/product-found');

        await scan(tester, kSparse);
        await until(
          tester,
          () => present(find.text('Chili crisp')),
          what: 'the sparse product',
        );
        await shot(tester, 'scan/product-found-sparse');

        await scan(tester, kUnknown);
        await until(
          tester,
          () => present(find.text(l10n.carousel_unknown_product_button)),
          what: 'the unknown product card',
        );
        await shot(tester, 'scan/product-unknown');

        Smooth.servers.offline = true;
        await scan(tester, kCola);
        await until(
          tester,
          () => present(find.text(l10n.carousel_error_button)),
          what: 'the error card',
        );
        await shot(tester, 'scan/product-error');
        Smooth.servers.offline = false;
      },
      'search': (WidgetTester tester) async {
        await Smooth.device(tester, const Start(searchHistory: _searches));
        await tap(tester, find.text('Search for a product'));
        await shot(tester, 'search/history');

        await search(tester, 'muesli');
        await until(
          tester,
          () => present(find.textContaining('Hazelnut spread')),
          what: 'the search results',
        );
        await shot(tester, 'search/results', grow: true);

        expect(await tapLabelled(tester, 'My personalised ranking'), isTrue);
        await until(
          tester,
          () => present(find.byType(PersonalizedRankingPage)),
          what: 'the personalised ranking',
        );
        await shot(tester, 'search/personalised-ranking', grow: true);
      },
      'search with no result': (WidgetTester tester) async {
        await tap(tester, find.text('Search for a product'));
        await search(tester, kNoResultTerm);
        await until(
          tester,
          () => present(find.text(l10n.world_results_action)),
          what: 'the empty search result',
        );
        await shot(tester, 'search/no-result');
      },
      'search offline': (WidgetTester tester) async {
        await tap(tester, find.text('Search for a product'));
        Smooth.servers.offline = true;
        await search(tester, 'granola bars');
        await until(
          tester,
          () => !present(find.textContaining('is in progress')),
          what: 'the search error',
        );
        await shot(tester, 'search/error');
        Smooth.servers.offline = false;
      },
    },
  );
}
