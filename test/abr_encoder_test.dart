import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'support/abr_fixture_builder.dart';

/// Exercises legacy reconstruction and modern section-based ABR writing.
void main() {
  group('AbrEncoder', () {
    test('round-trips every supported legacy sample layout', () {
      for (final Uint8List bytes in <Uint8List>[
        AbrFixtureBuilder.legacyComputed(),
        AbrFixtureBuilder.legacySampledRaw(),
        AbrFixtureBuilder.legacySampledPackBits16(),
        AbrFixtureBuilder.legacySampledBitmap1(),
      ]) {
        final AbrFile file = AbrDecoder.decode(bytes);

        final Uint8List encoded = AbrEncoder.encode(file);

        check(encoded).deepEquals(bytes);
      }
    });

    test('rebuilds all recognized modern sections from typed data', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[
          AbrFixtureBuilder.sampleSection(packBits: true),
          AbrFixtureBuilder.descriptorSection(),
          AbrFixtureBuilder.patternSection(),
          AbrFixtureBuilder.hierarchySection(),
        ],
      );
      final AbrFile file = AbrDecoder.decode(
        bytes,
        options: const AbrDecodeOptions(preserveSectionData: false),
      );

      final Uint8List encoded = AbrEncoder.encode(file);
      final AbrFile roundTrip = AbrDecoder.decode(encoded);

      check(encoded).deepEquals(bytes);
      check(roundTrip.samples.single.alpha).deepEquals(file.samples.single.alpha);
      check(roundTrip.brushes.single.name).equals(file.brushes.single.name);
      check(roundTrip.patterns.single.renderRgba8().rgba).deepEquals(file.patterns.single.renderRgba8().rgba);
      check(roundTrip.hierarchy.first.name).equals(file.hierarchy.first.name);
    });

    test('consolidates repeated sample sections without duplicating tips', () {
      final AbrFile file = AbrDecoder.decode(
        AbrFixtureBuilder.modern(
          sections: <AbrTestSection>[
            AbrFixtureBuilder.sampleSection(id: 'first'),
            AbrFixtureBuilder.sampleSection(id: 'second'),
          ],
        ),
      );

      final AbrFile roundTrip = AbrDecoder.decode(AbrEncoder.encode(file));

      check(roundTrip.samples.map((sample) => sample.id).toList()).deepEquals(<String>['first', 'second']);
      check(roundTrip.sections.where((section) => section.key == 'samp')).length.equals(1);
    });

    test('preserves unknown sections when their payload is available', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[
          AbrFixtureBuilder.unknownSection(),
        ],
      );
      final AbrFile file = AbrDecoder.decode(bytes);

      final Uint8List encoded = AbrEncoder.encode(file);

      check(encoded).deepEquals(bytes);
      check(AbrDecoder.decode(encoded).sections.single.data).deepEquals(<int>[1, 2, 3]);
    });

    test('preserves complete known sections in permissive mode', () {
      final AbrTestSection sample = AbrFixtureBuilder.sampleSection();
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[
          AbrTestSection(
            key: sample.key,
            data: Uint8List.fromList(<int>[...sample.data, 0x7f]),
          ),
        ],
      );
      final AbrFile file = AbrDecoder.decode(bytes);

      final Uint8List encoded = AbrEncoder.encode(
        file,
        options: const AbrEncodeOptions(mode: AbrEncodeMode.permissive),
      );

      check(file.warnings).isNotEmpty();
      check(encoded).deepEquals(bytes);
      check(AbrDecoder.decode(encoded).samples.single.alpha).deepEquals(file.samples.single.alpha);
    });

    test('requires retained trailing bytes only when they are included', () {
      final Uint8List container = AbrFixtureBuilder.modern(
        sections: const <AbrTestSection>[],
      );
      final Uint8List bytes = Uint8List.fromList(<int>[...container, 7, 8]);
      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.trailingData).deepEquals(<int>[7, 8]);
      check(file.trailingByteCount).equals(2);
      check(() => AbrEncoder.encode(file)).throws<AbrWriteException>();
      check(
        AbrEncoder.encode(
          file,
          options: const AbrEncodeOptions(mode: AbrEncodeMode.permissive),
        ),
      ).deepEquals(bytes);

      final AbrFile unpreserved = AbrDecoder.decode(
        bytes,
        options: const AbrDecodeOptions(preserveTrailingData: false),
      );
      check(unpreserved.trailingData).isEmpty();
      check(unpreserved.trailingByteCount).equals(2);
      check(
        () => AbrEncoder.encode(
          unpreserved,
          options: const AbrEncodeOptions(mode: AbrEncodeMode.permissive),
        ),
      ).throws<AbrWriteException>();
      check(
        AbrEncoder.encode(
          unpreserved,
          options: const AbrEncodeOptions(includeTrailingData: false),
        ),
      ).deepEquals(container);
    });

    test('requires preserved unknown payloads unless they are excluded', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[
          AbrFixtureBuilder.unknownSection(),
        ],
      );
      final AbrFile file = AbrDecoder.decode(
        bytes,
        options: const AbrDecodeOptions(preserveSectionData: false),
      );

      check(() => AbrEncoder.encode(file)).throws<AbrWriteException>();
      check(
        AbrDecoder.decode(
          AbrEncoder.encode(
            file,
            options: const AbrEncodeOptions(includeUnknownSections: false),
          ),
        ).sections,
      ).isEmpty();
    });

    test('omits pattern and hierarchy sections when requested', () {
      final AbrFile file = AbrDecoder.decode(
        AbrFixtureBuilder.modern(
          sections: <AbrTestSection>[
            AbrFixtureBuilder.patternSection(),
            AbrFixtureBuilder.hierarchySection(),
          ],
        ),
      );

      final AbrFile roundTrip = AbrDecoder.decode(
        AbrEncoder.encode(
          file,
          options: const AbrEncodeOptions(
            includePatterns: false,
            includeHierarchy: false,
          ),
        ),
      );

      check(roundTrip.patterns).isEmpty();
      check(roundTrip.hierarchy).isEmpty();
      check(roundTrip.sections).isEmpty();
    });
  });
}
