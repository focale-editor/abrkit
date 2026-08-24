import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Exercises decoding against captured Photoshop brush libraries.
void main() {
  group('Photoshop 2026 corpus', () {
    test('decodes the captured shape, scatter, and transfer dynamics preset', () {
      final Uint8List bytes = _readFixture('photoshop_dynamics.abr.b64');

      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.warnings).isEmpty();
      check(file.brushes).length.equals(1);
      check(file.samples).length.equals(1);
      final AbrBrush brush = file.brushes.single;
      check(brush.name).equals('Patchy Dynamics Probe Dyn');
      check(brush.settings).isNotNull();
      check(brush.settings!.shapeDynamics).isNotNull();
      check(brush.settings!.scatter).isNotNull();
      check(brush.settings!.transfer).isNotNull();
      check(brush.settings!.dualBrush).isNull();
      check(file.sampleFor(brush.shape as AbrSampledBrushShape)).isNotNull();
      check(file.samples.single.trailingData).length.equals(8);
    });

    test('decodes the captured dual-brush preset', () {
      final Uint8List bytes = _readFixture('photoshop_dual_brush.abr.b64');

      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.warnings).isEmpty();
      check(file.brushes.single.name).equals('Patchy Dual Probe');
      check(file.brushes.single.settings).isNotNull();
      check(file.brushes.single.settings!.dualBrush).isNotNull();
      check(file.brushes.single.settings!.scatter).isNotNull();
      check(file.brushes.single.settings!.transfer).isNotNull();
    });
  });
}

/// Decodes a line-wrapped base64 fixture tracked as reviewable text.
Uint8List _readFixture(String name) {
  final String encoded = File('test/fixtures/$name').readAsStringSync().replaceAll(RegExp(r'\s'), '');
  return base64Decode(encoded);
}
