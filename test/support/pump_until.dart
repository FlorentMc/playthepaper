import 'package:flutter_test/flutter_test.dart';

/// Pumps frames until [condition] holds, for tests that wait on real disk
/// writes under [WidgetTester.runAsync]. A fixed sleep is not reliable on a
/// loaded machine; polling with a generous ceiling is.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('pumpUntil timed out after $timeout${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
    await tester.pump();
  }
  await tester.pump();
}
