import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'support/abr_fixture_builder.dart';

/// Exercises modern section-based ABR decoding.
void main() {
  group('modern ABR', () {
    test('decodes samples, descriptors, patterns, hierarchy, and unknown sections', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[
          AbrFixtureBuilder.sampleSection(),
          AbrFixtureBuilder.descriptorSection(),
          AbrFixtureBuilder.patternSection(),
          AbrFixtureBuilder.hierarchySection(),
          AbrFixtureBuilder.unknownSection(),
        ],
      );

      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.version).equals(6);
      check(file.subversion).equals(2);
      check(file.family).equals(AbrFormatFamily.modern);
      check(file.sections).length.equals(5);
      check(file.samples).length.equals(1);
      check(file.brushes).length.equals(1);
      check(file.patterns).length.equals(1);
      check(file.hierarchy).length.equals(2);
      check(file.descriptors).length.equals(1);
      check(file.hierarchyDescriptors).length.equals(1);
      check(file.warnings).isNotEmpty();

      final AbrSample sample = file.samples.single;
      check(sample.id).equals('sample-id');
      check(sample.alpha).deepEquals(<int>[0, 64, 128, 255]);
      final AbrBrush brush = file.brushes.single;
      check(brush.name).equals('Synthetic brush');
      final AbrSampledBrushShape shape = brush.shape as AbrSampledBrushShape;
      check(shape.sampleId).equals(sample.id);
      check(shape.diameter).equals(24);
      check(shape.roundness).isCloseTo(0.8, 0.000001);
      check(shape.flipY).isTrue();
      check(file.sampleFor(shape)).identicalTo(sample);

      final AbrBrushSettings settings = brush.settings!;
      check(settings.noise).isTrue();
      check(settings.wetEdges).isTrue();
      check(settings.buildUp).isTrue();
      check(settings.shapeDynamics).isNotNull();
      check(settings.shapeDynamics!.size.control).equals(AbrDynamicsControl.penPressure);
      check(settings.shapeDynamics!.size.jitter).isCloseTo(0.4, 0.000001);
      check(settings.scatter!.count).equals(3);
      check(settings.texture!.patternId).equals('pattern-id');
      check(settings.texture!.scale).isCloseTo(1.25, 0.000001);
      check(settings.colorDynamics!.purity).isCloseTo(-0.25, 0.000001);
      check(settings.transfer!.opacity.minimum).isCloseTo(0.1, 0.000001);
      check(settings.pose!.pressure).isCloseTo(0.55, 0.000001);
      check(settings.toolOptions!.flow).equals(75);
      check(settings.toolOptions!.smoothing).isTrue();
      check(settings.rawDescriptor.value('future')).isNull();

      final AbrPattern pattern = file.patterns.single;
      check(pattern.id).equals('pattern-id');
      check(pattern.colorMode).equals(AbrColorMode.rgb);
      check(pattern.channels).length.equals(3);
      check(pattern.channels.first.decodedData).isNotNull().deepEquals(<int>[255, 0, 0, 255]);
      check(file.hierarchy.first.name).equals('Favorites');
      check(file.sections.last.data).deepEquals(<int>[1, 2, 3]);
    });

    for (final int version in <int>[6, 7, 9, 10]) {
      test('accepts modern major version $version and subversion 1', () {
        final Uint8List bytes = AbrFixtureBuilder.modern(
          version: version,
          subversion: 1,
          sections: <AbrTestSection>[
            AbrFixtureBuilder.sampleSection(subversion: 1, depth: 16, packBits: true),
            AbrFixtureBuilder.descriptorSection(),
          ],
        );

        final AbrFile file = AbrDecoder.decode(bytes);

        check(file.version).equals(version);
        check(file.subversion).equals(1);
        check(file.samples.single.alpha).deepEquals(<int>[0, 64, 128, 255]);
        check(file.samples.single.alpha16).isNotNull();
      });
    }
  });
}
