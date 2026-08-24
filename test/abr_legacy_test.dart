import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'support/abr_fixture_builder.dart';

/// Exercises legacy ABR decoding and compatibility behavior.
void main() {
  group('legacy ABR', () {
    test('decodes every documented version 1 computed field', () {
      final Uint8List bytes = AbrFixtureBuilder.legacyComputed();

      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.version).equals(1);
      check(file.family).equals(AbrFormatFamily.legacy);
      check(file.brushes).length.equals(1);
      final AbrBrush brush = file.brushes.single;
      check(brush.rawData).isNotNull();
      check(brush.shape).isA<AbrComputedBrushShape>();
      final AbrComputedBrushShape shape = brush.shape as AbrComputedBrushShape;
      check(shape.diameter).equals(41);
      check(shape.spacing).isCloseTo(0.25, 0.000001);
      check(shape.roundness).isCloseTo(0.75, 0.000001);
      check(shape.angle).equals(-30);
      check(shape.hardness).isCloseTo(0.6, 0.000001);
      check(file.samples).isEmpty();
    });

    test('decodes a named version 2 raw sampled brush', () {
      final Uint8List bytes = AbrFixtureBuilder.legacySampledRaw();

      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.version).equals(2);
      check(file.samples).length.equals(1);
      final AbrSample sample = file.samples.single;
      check(sample.name).equals('Éponge');
      check(sample.bounds.left).equals(-2);
      check(sample.bounds.top).equals(-1);
      check(sample.alpha).deepEquals(<int>[0, 64, 128, 255]);
      check(sample.alphaAt(x: 1, y: 1)).equals(255);
      final AbrSampledBrushShape shape = file.brushes.single.shape as AbrSampledBrushShape;
      check(shape.sampleId).equals(sample.id);
      check(file.sampleFor(shape)).identicalTo(sample);
    });

    test('decodes PackBits-compressed 16-bit samples without losing precision', () {
      final Uint8List bytes = AbrFixtureBuilder.legacySampledPackBits16();

      final AbrFile file = AbrDecoder.decode(bytes);

      final AbrSample sample = file.samples.single;
      check(sample.depth).equals(16);
      check(sample.compression).equals(AbrCompression.packBits);
      check(sample.alpha).deepEquals(<int>[0, 128, 255, 64]);
      check(sample.alpha16).isNotNull().deepEquals(<int>[0, 0x8000, 0xffff, 0x4000]);
    });

    test('honors byte padding at the end of every 1-bit row', () {
      final Uint8List bytes = AbrFixtureBuilder.legacySampledBitmap1();

      final AbrSample sample = AbrDecoder.decode(bytes).samples.single;

      check(sample.alpha).deepEquals(<int>[255, 0, 255, 0, 255, 0, 255, 0, 255, 0]);
    });
  });
}
