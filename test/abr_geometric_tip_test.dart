import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

/// Exercises generated geometric samples and descriptor synthesis.
void main() {
  group('geometric sampled tips', () {
    test('rasterizes a symmetric soft square', () {
      final AbrSample sample = AbrSample.square(
        id: 'square',
        sampleSize: 5,
        hardness: 0.5,
      );

      check(sample.width).equals(5);
      check(sample.height).equals(5);
      check(sample.depth).equals(8);
      check(sample.alphaAt(x: 2, y: 2)).equals(255);
      check(sample.alphaAt(x: 0, y: 0)).isLessThan(sample.alphaAt(x: 2, y: 2));
      check(sample.alphaAt(x: 0, y: 0)).equals(sample.alphaAt(x: 4, y: 4));
      check(sample.alphaAt(x: 0, y: 2)).equals(sample.alphaAt(x: 2, y: 0));
    });

    test('retains generated 16-bit precision', () {
      final AbrSample sample = AbrSample.square(
        id: 'soft-square',
        sampleSize: 3,
        hardness: 0,
        depth: 16,
      );

      final Uint16List alpha16 = sample.alpha16!;
      check(alpha16).length.equals(9);
      check(alpha16[4]).isGreaterThan(alpha16[0]);
      check(sample.alpha[0]).equals(alpha16[0] >> 8);
      check(sample.alpha[4]).equals(alpha16[4] >> 8);

      final AbrFile roundTrip = AbrDecoder.decode(
        AbrEncoder.encode(
          AbrFile.modern(
            brushes: [
              AbrBrush.sampled(
                name: 'Soft square',
                sampleId: sample.id,
                diameter: 24,
              ),
            ],
            samples: [sample],
          ),
        ),
        options: const AbrDecodeOptions(mode: AbrDecodeMode.strict),
      );
      check(roundTrip.samples.single.alpha16).isNotNull().deepEquals(alpha16);
    });

    test('shares one square sample with a descriptor-rotated diamond', () {
      final AbrSample squareSample = AbrSample.square(
        id: 'canonical-square',
        name: 'Canonical square',
        sampleSize: 32,
      );
      final AbrFile source = AbrFile.modern(
        brushes: [
          AbrBrush.sampled(
            name: 'Square',
            sampleId: squareSample.id,
            shapeName: squareSample.name,
            diameter: 64,
          ),
          AbrBrush.sampled(
            name: 'Diamond',
            sampleId: squareSample.id,
            shapeName: squareSample.name,
            diameter: 64,
            angle: 45,
          ),
        ],
        samples: [squareSample],
      );

      final AbrFile roundTrip = AbrDecoder.decode(
        AbrEncoder.encode(source),
        options: const AbrDecodeOptions(mode: AbrDecodeMode.strict),
      );
      final AbrSampledBrushShape square = roundTrip.brushes[0].shape as AbrSampledBrushShape;
      final AbrSampledBrushShape diamond = roundTrip.brushes[1].shape as AbrSampledBrushShape;

      check(roundTrip.samples).length.equals(1);
      check(roundTrip.warnings).isEmpty();
      check(roundTrip.brushes.map((brush) => brush.name).toList()).deepEquals(['Square', 'Diamond']);
      check(square.sampleId).equals(squareSample.id);
      check(diamond.sampleId).equals(squareSample.id);
      check(square.angle).equals(0);
      check(diamond.angle).equals(45);
      check(roundTrip.sampleFor(square)).identicalTo(roundTrip.sampleFor(diamond));
    });

    test('synthesizes computed descriptors for new modern libraries', () {
      final AbrFile source = AbrFile.modern(
        brushes: [
          AbrBrush(
            name: 'Round',
            shape: const AbrComputedBrushShape(
              diameter: 48,
              hardness: 0.75,
              angle: -15,
              roundness: 0.8,
              spacing: 0.2,
              spacingEnabled: true,
              flipX: false,
              flipY: true,
              rawDescriptor: null,
            ),
          ),
        ],
      );

      final AbrFile roundTrip = AbrDecoder.decode(
        AbrEncoder.encode(source),
        options: const AbrDecodeOptions(mode: AbrDecodeMode.strict),
      );
      final AbrComputedBrushShape shape = roundTrip.brushes.single.shape as AbrComputedBrushShape;

      check(roundTrip.brushes.single.name).equals('Round');
      check(shape.diameter).equals(48);
      check(shape.hardness).equals(0.75);
      check(shape.angle).equals(-15);
      check(shape.roundness).equals(0.8);
      check(shape.spacing).equals(0.2);
      check(shape.flipY).isTrue();
    });

    test('rejects invalid rasterization parameters', () {
      check(
        () => AbrSample.square(
          id: 'invalid',
          sampleSize: 0,
        ),
      ).throws<RangeError>();
      check(
        () => AbrSample.square(
          id: 'invalid',
          sampleSize: 8,
          hardness: 1.1,
        ),
      ).throws<RangeError>();
      check(
        () => AbrSample.square(
          id: 'invalid',
          sampleSize: 8,
          depth: 1,
        ),
      ).throws<ArgumentError>();
    });

    test('rejects a generated preset whose sample is missing', () {
      final AbrFile source = AbrFile.modern(
        brushes: [
          AbrBrush.sampled(
            name: 'Missing',
            sampleId: 'missing',
            diameter: 32,
          ),
        ],
      );

      check(() => AbrEncoder.encode(source)).throws<AbrWriteException>();
    });
  });
}
