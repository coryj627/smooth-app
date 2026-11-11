// Accessibility audit, part 6 of 6: the profile tab, every preferences page
// under it, and the account pages.  See README.md in this directory.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/fixtures.dart';

Future<void> openProfile(WidgetTester tester) =>
    tap(tester, find.text(l10n.profile_navbar_label));

/// Opens the entry called [entry] of the profile page.
Future<void> openSection(WidgetTester tester, String entry) async {
  await openProfile(tester);
  await tap(tester, find.text(entry));
}

/// Opens the entry called [entry] of the profile page and audits what it
/// leads to.
Part section(String entry, String screenId) => (WidgetTester tester) async {
  await openSection(tester, entry);
  await shot(tester, screenId, grow: true);
};

/// Types in the field labelled [label].
Future<void> type(WidgetTester tester, String label, String text) async {
  await tester.enterText(
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField)),
    text,
  );
  await settle(tester, rounds: 1);
}

void main() {
  walk('preferences', const Start(history: kListBarcodes), <String, Part>{
    'profile': (WidgetTester tester) async {
      await openProfile(tester);
      await shot(tester, 'preferences/profile-signed-out', grow: true);
    },
    'search for a setting': (WidgetTester tester) async {
      await openProfile(tester);
      await tester.enterText(find.byType(TextField).first, 'language');
      await settle(tester);
      await shot(tester, 'preferences/search-results', grow: true);
      await tester.enterText(find.byType(TextField).first, '');
      await settle(tester);
    },
    'food preferences': (WidgetTester tester) async {
      await openSection(tester, 'Food Preferences');
      await shot(tester, 'preferences/food', grow: true);
    },
    'app settings': (WidgetTester tester) async {
      await openSection(tester, l10n.myPreferences_settings_title);
      await shot(tester, 'preferences/app-settings', grow: true);
      for (final (String entry, String id) in <(String, String)>[
        ('Theme', 'theme'),
        ('Your language', 'language'),
        ('Your country', 'country'),
        ('Your currency', 'currency'),
        ('Choose image source', 'image-source'),
      ]) {
        await tap(tester, find.text(entry));
        await shot(tester, 'preferences/app-settings-$id');
        if (present(find.byTooltip('Close'))) {
          await tap(tester, find.byTooltip('Close').last);
        } else {
          await back(tester);
        }
      }
    },
    'contribute': section(
      l10n.preferences_page_contribute_project_title,
      'preferences/contribute',
    ),
    'faq': section(l10n.preferences_faq_subtitle, 'preferences/faq'),
    'connect': section(l10n.preferences_connect_title, 'preferences/connect'),
    'about': section(l10n.preferences_about_app_title, 'preferences/about'),
    'legal': (WidgetTester tester) async {
      await openSection(tester, l10n.preferences_legal_information_title);
      await shot(tester, 'preferences/legal');
      await tap(tester, find.text('Licenses'));
      await shot(tester, 'preferences/licenses');
    },
    'donation': section(l10n.preferences_support_title, 'donation/page'),
    'contributions': section(
      l10n.preferences_complete_products,
      'preferences/contributions',
    ),
    'prices': section(l10n.preferences_add_prices, 'prices/home'),
    'hunger games': (WidgetTester tester) async {
      await openSection(tester, 'Hunger Games');
      await shot(tester, 'hunger-games/questions');
      await tap(tester, find.byTooltip('Close'));
    },
    'sign in': (WidgetTester tester) async {
      await openProfile(tester);
      expect(await tapLabelled(tester, l10n.sign_in), isTrue);
      await shot(tester, 'account/login', grow: true);

      // Submitted empty: the form's own validation messages.
      await tap(tester, find.widgetWithText(ElevatedButton, l10n.sign_in));
      await shot(tester, 'account/login-empty-fields');

      await type(tester, l10n.username_or_email, kUserId);
      await type(tester, l10n.password, 'not-the-password');
      await tap(tester, find.widgetWithText(ElevatedButton, l10n.sign_in));
      await shot(tester, 'account/login-wrong-password');

      await tap(tester, find.textContaining(l10n.forgot_password));
      await shot(tester, 'account/forgot-password');
    },
    'sign up': (WidgetTester tester) async {
      await openProfile(tester);
      expect(await tapLabelled(tester, l10n.create_account), isTrue);
      await shot(tester, 'account/sign-up', grow: true);
    },
    'signed in': (WidgetTester tester) async {
      await openProfile(tester);
      expect(await tapLabelled(tester, l10n.sign_in), isTrue);
      await type(tester, l10n.username_or_email, kUserId);
      await type(tester, l10n.password, kPassword);
      await tap(tester, find.widgetWithText(ElevatedButton, l10n.sign_in));
      await until(
        tester,
        () => !present(find.text(l10n.sign_in_text)),
        what: 'the end of the sign-in',
      );
      await Smooth.home(tester);
      await openProfile(tester);
      await shot(tester, 'preferences/profile-signed-in', grow: true);
      await tap(tester, find.byTooltip('Manage your account'));
      await shot(tester, 'account/manage', grow: true);
    },
  });
}
