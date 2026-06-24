// Smoke test dasar untuk aplikasi Notula.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notula/screens/home_screen.dart';

void main() {
  testWidgets('Home menampilkan judul & tombol Rekam', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();

    expect(find.text('Notula'), findsOneWidget);
    expect(find.text('Rekam'), findsOneWidget);
  });
}
