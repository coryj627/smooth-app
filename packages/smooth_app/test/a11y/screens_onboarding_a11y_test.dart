// Accessibility audit, part 1 of 6: a first run of the app, from the welcome
// page to the end of the onboarding.  See README.md in this directory.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/pages/onboarding/onboarding_flow_navigator.dart';

import 'support/app.dart';

void main() {
  walk(
    'onboarding',
    const Start(
      onboarding: OnboardingPage.NOT_STARTED,
      cameraPermission: 'denied',
    ),
    <String, Part>{
      'onboarding': (WidgetTester tester) async {
        await shot(tester, 'onboarding/home');
        await tap(tester, find.text(l10n.onboarding_home_welcome_text1).first);
        await tap(tester, find.text('Continue'));
        await shot(tester, 'onboarding/country');

        await tap(tester, find.text('United States'));
        await shot(tester, 'onboarding/country-picker');
        await tap(tester, find.byTooltip('Close'));

        await tap(tester, find.byKey(const Key('nextAfterWelcome')));
        await shot(tester, 'onboarding/health-card', grow: true);
        await tap(tester, find.text('Nutri-Score A'));
        await shot(tester, 'onboarding/health-card-nutriscore', grow: true);
        await back(tester);

        await tap(tester, find.byKey(const Key('nextAfterHealth')));
        await shot(tester, 'onboarding/eco-card', grow: true);

        await tap(tester, find.byKey(const Key('nextAfterEco')));
        await shot(tester, 'onboarding/preferences', grow: true);

        await tap(tester, find.byKey(const Key('nextAfterPreferences')));
        await shot(tester, 'onboarding/permissions');
        await tap(tester, find.text(l10n.ask_me_later_button_label));
        await shot(tester, 'scan/camera-permission-denied');
      },
    },
  );
}
