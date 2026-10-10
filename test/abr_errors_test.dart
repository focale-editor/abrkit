import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'support/abr_fixture_builder.dart';

/// Exercises malformed-input handling and resource limits.
void main() {
  group('ABR validation', () {
    test('rejects an unknown major version', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0, 8]);

      check(() => AbrDecoder.decode(bytes)).throws<AbrFormatException>();
    });

    test('rejects input above the configured file limit', () {
      final Uint8List bytes = AbrFixtureBuilder.legacyComputed();
      final AbrDecodeOptions options = AbrDecodeOptions(maxFileBytes: bytes.length - 1);

      check(() => AbrDecoder.decode(bytes, options: options)).throws<AbrFormatException>();
    });

    test('strict mode rejects a section length beyond the file bounds', () {
      final Uint8List bytes =
          (PsBinaryWriter()
                ..writeUint16(6)
                ..writeUint16(2)
                ..writeString('8BIM')
                ..writeString('samp')
                ..writeUint32(100))
              .takeBytes();

      check(() => AbrDecoder.decode(bytes, options: const AbrDecodeOptions(mode: AbrDecodeMode.strict))).throws<AbrFormatException>();
    });

    test('tolerant mode recovers the complete tips of a truncated file', () {
      // A sample section cut off in its second entry, as in an incomplete download.
      final Uint8List complete = AbrFixtureBuilder.sampleSection().data;
      final Uint8List bytes =
          (PsBinaryWriter()
                ..writeUint16(6)
                ..writeUint16(2)
                ..writeString('8BIM')
                ..writeString('samp')
                ..writeUint32(complete.length + 1000)
                ..writeBytes(complete)
                ..writeUint32(996)
                ..writeBytes(Uint8List(40)))
              .takeBytes();

      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.samples).length.equals(1);
      check(file.samples.single.id).equals('sample-id');
      check(file.warnings.map((warning) => warning.message)).any((message) => message.contains('truncated'));
      check(AbrDecoder.decode(AbrEncoder.encode(file)).samples).length.equals(1);
    });

    test('strict mode rejects an unknown tagged section', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(sections: <AbrTestSection>[AbrFixtureBuilder.unknownSection()]);

      check(
        () => AbrDecoder.decode(bytes, options: const AbrDecodeOptions(mode: AbrDecodeMode.strict)),
      ).throws<AbrFormatException>();
    });

    test('can avoid retaining large section payloads', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(sections: <AbrTestSection>[AbrFixtureBuilder.unknownSection()]);

      final AbrFile file = AbrDecoder.decode(bytes, options: const AbrDecodeOptions(preserveSectionData: false));

      check(file.sections.single.data).isEmpty();
      check(file.warnings).isNotEmpty();
    });

    test('accepts an unpadded final tagged section used by real exporters', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[AbrFixtureBuilder.unknownSection()],
        padFinalSection: false,
      );

      final AbrFile file = AbrDecoder.decode(bytes);

      check(file.sections.single.data).deepEquals(<int>[1, 2, 3]);
    });

    test('counts only pixel buffers retained by decoded samples', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[AbrFixtureBuilder.sampleSection()],
      );

      final AbrFile file = AbrDecoder.decode(
        bytes,
        options: const AbrDecodeOptions(maxDecodedPixelBytes: 4),
      );

      check(file.samples).length.equals(1);
      check(file.warnings).isEmpty();
    });

    test('applies caller-selected Action Descriptor limits', () {
      final Uint8List bytes = AbrFixtureBuilder.modern(
        sections: <AbrTestSection>[AbrFixtureBuilder.descriptorSection()],
      );

      check(
        () => AbrDecoder.decode(
          bytes,
          options: const AbrDecodeOptions(
            mode: AbrDecodeMode.strict,
            descriptorOptions: PsDescriptorDecodeOptions(maxValues: 0),
          ),
        ),
      ).throws<AbrFormatException>();
    });
  });
}
