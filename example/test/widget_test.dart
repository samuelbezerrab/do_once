import 'package:do_once/do_once.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_execution_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Do.revoke(key: 'showConfetti', scope: DoScope.session);
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
    await tester.pump();
  }

  Future<void> finishCelebration(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  Future<void> selectScope(WidgetTester tester, String label) async {
    await tapVisible(tester, find.byType(DropdownButton<DoScope>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('starts without a title bar or confetti placeholder',
      (tester) async {
    await tester.pumpWidget(const DoOnceExample());
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.celebration_outlined), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Activity log'), findsOneWidget);
  });

  for (final scope in [
    'Session',
    'Until reset',
    'Hourly',
    'Daily',
    'Monthly',
    'Yearly'
  ]) {
    testWidgets('$scope celebrates once and can be reset', (tester) async {
      await tester.pumpWidget(const DoOnceExample());
      await tester.pumpAndSettle();
      if (scope != 'Until reset') await selectScope(tester, scope);

      expect(find.text('Status: Not completed'), findsOneWidget);
      await tapVisible(tester, find.text('Celebrate'));
      expect(find.bySemanticsLabel('Confetti celebration'), findsOneWidget);
      expect(find.text('• $scope: action ran!'), findsOneWidget);
      await finishCelebration(tester);
      expect(find.text('Status: Completed'), findsOneWidget);
      expect(find.bySemanticsLabel('Confetti celebration'), findsNothing);

      await tapVisible(tester, find.text('Celebrate'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Confetti celebration'), findsNothing);
      expect(find.text('• $scope: already completed; action skipped.'),
          findsOneWidget);

      await tapVisible(tester, find.text('Reset completion'));
      await tester.pumpAndSettle();
      expect(find.text('Status: Not completed'), findsOneWidget);

      await tapVisible(tester, find.text('Celebrate'));
      expect(find.bySemanticsLabel('Confetti celebration'), findsOneWidget);
      await finishCelebration(tester);
    });
  }

  testWidgets('completion is independent across scopes', (tester) async {
    await tester.pumpWidget(const DoOnceExample());
    await tester.pumpAndSettle();
    await selectScope(tester, 'Session');
    await tapVisible(tester, find.text('Celebrate'));
    await finishCelebration(tester);

    await selectScope(tester, 'Daily');
    expect(find.text('Status: Not completed'), findsOneWidget);
    await tapVisible(tester, find.text('Celebrate'));
    await finishCelebration(tester);

    await selectScope(tester, 'Session');
    expect(find.text('Status: Completed'), findsOneWidget);
    await tapVisible(tester, find.text('Reset completion'));
    await tester.pumpAndSettle();

    await selectScope(tester, 'Daily');
    expect(find.text('Status: Completed'), findsOneWidget);
  });

  testWidgets('a skipped call does not restart an active celebration',
      (tester) async {
    await tester.pumpWidget(const DoOnceExample());
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Celebrate'));
    final image = find.byType(Image);
    final originalKey = tester.widget<Image>(image).key;

    await tester.tap(find.text('Celebrate'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Image>(image).key, originalKey);
    expect(find.text('• Until reset: already completed; action skipped.'),
        findsOneWidget);
    await finishCelebration(tester);
    expect(image, findsNothing);
  });

  testWidgets('activity log keeps only the two most recent entries',
      (tester) async {
    await tester.pumpWidget(const DoOnceExample());
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Celebrate'));
    await finishCelebration(tester);
    await tapVisible(tester, find.text('Celebrate'));
    await tester.pumpAndSettle();
    expect(find.text('• Choose a scope and celebrate.'), findsNothing);
    expect(find.text('• Until reset: action ran!'), findsOneWidget);
    expect(find.text('• Until reset: already completed; action skipped.'),
        findsOneWidget);

    await tapVisible(tester, find.text('Reset completion'));
    await tester.pumpAndSettle();
    expect(find.text('• Until reset: action ran!'), findsNothing);
    expect(find.text('• Until reset: already completed; action skipped.'),
        findsOneWidget);
    expect(find.text('• Until reset: completion reset.'), findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('celebration works at ${size.width}x${size.height}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const DoOnceExample());
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Celebrate'));
      expect(find.bySemanticsLabel('Confetti celebration'), findsOneWidget);
      if (size.width > size.height) {
        final confetti = find.byType(Image);
        expect(tester.getCenter(confetti).dx,
            greaterThan(tester.getCenter(find.text('Celebrate')).dx));
        expect(tester.getTopLeft(find.text('Activity log')).dy,
            greaterThan(tester.getBottomLeft(confetti).dy));
      }
      await finishCelebration(tester);
      await tapVisible(tester, find.text('Reset completion'));
      await tester.pumpAndSettle();
      expect(find.text('Status: Not completed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
