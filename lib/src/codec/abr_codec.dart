import 'dart:convert';
import 'dart:typed_data';

import 'package:abrkit/src/codec/abr_decoder.dart';
import 'package:abrkit/src/codec/abr_encoder.dart';
import 'package:abrkit/src/model/abr_file.dart';
import 'package:abrkit/src/model/abr_options.dart';

/// Converts ABR models to and from their binary representation.
///
/// Each conversion handles one complete in-memory file. The encoded type is
/// [List<int>] so this codec can be composed with standard `dart:convert`
/// codecs, while [encode] keeps the more precise [Uint8List] return type.
final class AbrCodec extends Codec<AbrFile, List<int>> {
  /// Options applied while decoding.
  final AbrDecodeOptions decodeOptions;

  /// Options applied while encoding.
  final AbrEncodeOptions encodeOptions;

  /// Creates a reusable codec with fixed decoding and encoding options.
  const AbrCodec({
    this.decodeOptions = const AbrDecodeOptions(),
    this.encodeOptions = const AbrEncodeOptions(),
  });

  @override
  AbrDecoder get decoder => AbrDecoder(options: decodeOptions);

  @override
  AbrEncoder get encoder => AbrEncoder(options: encodeOptions);

  @override
  Uint8List encode(AbrFile input) => encoder.convert(input);
}
