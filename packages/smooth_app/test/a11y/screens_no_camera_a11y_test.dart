// Accessibility audit, a small extra part: the scan tab on a device with no
// camera.  The app decides this once, when it starts, so it needs a start of
// its own.  See README.md in this directory.
import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';

void main() {
  walk('no camera', const Start(hasCamera: false), <String, Part>{
    'scan': (WidgetTester tester) async {
      await shot(tester, 'scan/no-camera');
    },
  });
}
