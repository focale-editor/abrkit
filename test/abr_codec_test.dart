import 'dart:convert';
import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'support/abr_fixture_builder.dart';

/// Exercises the reusable `dart:convert` ABR interface.
void main() {
  group('AbrCodec', () {
    test('converts complete files and composes with base64', () {
      const AbrCodec codec = AbrCodec(
        decodeOptions: AbrDecodeOptions(mode: AbrDecodeMode.tolerant),
        encodeOptions: AbrEncodeOptions(mode: AbrEncodeMode.strict),
      );
      final Uint8List bytes = AbrFixtureBuilder.legacyComputed();

      final AbrFile file = codec.decode(bytes.toList(growable: false));
      final Uint8List encoded = codec.encode(file);
      final Codec<AbrFile, String> base64Codec = codec.fuse(base64);
      final AbrFile decodedBase64 = base64Codec.decode(base64Codec.encode(file));

      check(encoded).deepEquals(bytes);
      check(decodedBase64.version).equals(file.version);
      check(codec.decoder.options.mode).equals(AbrDecodeMode.tolerant);
      check(codec.encoder.options.mode).equals(AbrEncodeMode.strict);
    });
  });
}
