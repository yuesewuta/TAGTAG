import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagtag/main.dart';
import 'package:tagtag/storage/library_locator.dart';

void main() {
  testWidgets('shows a useful error when the storage root picker fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      TagTagApp(
        locator: _EmptyLibraryLocator(),
        storageRootPicker: () async => throw StateError('picker unavailable'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('选择存储根目录'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('picker unavailable'), findsOneWidget);
  });
}

class _EmptyLibraryLocator extends LibraryLocator {
  @override
  Future<Directory?> loadRoot() async => null;
}
