import 'dart:typed_data';

import 'package:abrkit/src/model/abr_sample.dart';
import 'package:pscore/pscore.dart';

/// Decodes grayscale bitmap payloads shared by samples and pattern channels.
abstract final class AbrBitmapDecoder {
  /// Decodes one raw or row-compressed planar bitmap from [reader].
  static ({Uint8List bytes, Uint16List? samples16}) decode({
    required PsBinaryReader reader,
    required int width,
    required int height,
    required int depth,
    required AbrCompression compression,
    bool wideRowLengths = false,
  }) {
    final int rowBytes = _rowBytes(width, depth);
    final int decodedLength = rowBytes * height;
    final Uint8List bytes = switch (compression) {
      AbrCompression.raw => reader.readBytes(decodedLength),
      AbrCompression.packBits => _decodePackBitsRows(
        reader: reader,
        rowBytes: rowBytes,
        height: height,
        wideRowLengths: wideRowLengths,
      ),
      AbrCompression.unknown => throw PsFormatException(
        message: 'Unsupported ABR bitmap compression',
        source: reader.bytes,
        offset: reader.baseOffset + reader.offset,
      ),
    };
    if (depth != 16) {
      return (bytes: bytes, samples16: null);
    }
    final ByteData data = ByteData.sublistView(bytes);
    final Uint16List samples = Uint16List(width * height);
    for (int index = 0; index < samples.length; index++) {
      samples[index] = data.getUint16(index * 2);
    }
    return (bytes: bytes, samples16: samples);
  }

  /// Converts decoded source bytes to one normalized 8-bit sample per pixel.
  static Uint8List normalizeTo8Bit({
    required Uint8List bytes,
    required int width,
    required int height,
    required int depth,
  }) {
    final int pixelCount = width * height;
    return switch (depth) {
      1 => _expandBitmap(bytes, width, height),
      8 => Uint8List.fromList(bytes),
      16 => Uint8List.fromList(<int>[for (int index = 0; index < pixelCount; index++) bytes[index * 2]]),
      _ => throw PsFormatException(message: 'Unsupported ABR bitmap depth $depth'),
    };
  }

  /// Returns the byte width of one packed planar row.
  static int _rowBytes(int width, int depth) {
    if (width <= 0 || depth != 1 && depth != 8 && depth != 16) {
      throw PsFormatException(message: 'Unsupported ABR bitmap geometry: width $width at $depth bits');
    }
    return (width * depth + 7) ~/ 8;
  }

  /// Decodes independently compressed PackBits rows and their length table.
  static Uint8List _decodePackBitsRows({
    required PsBinaryReader reader,
    required int rowBytes,
    required int height,
    required bool wideRowLengths,
  }) {
    final List<int> lengths = <int>[];
    for (int row = 0; row < height; row++) {
      lengths.add(wideRowLengths ? reader.readUint32() : reader.readUint16());
    }
    final Uint8List output = Uint8List(rowBytes * height);
    for (int row = 0; row < height; row++) {
      final Uint8List encoded = reader.readBytes(lengths[row]);
      final Uint8List decoded = PsPackBitsCodec.decodeRow(encoded, decodedLength: rowBytes);
      output.setRange(row * rowBytes, (row + 1) * rowBytes, decoded);
    }
    return output;
  }

  /// Expands row-padded, most-significant-bit-first bitmap samples.
  static Uint8List _expandBitmap(Uint8List bytes, int width, int height) {
    final int rowBytes = (width + 7) ~/ 8;
    final Uint8List output = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int bit = bytes[y * rowBytes + x ~/ 8] & (0x80 >> (x % 8));
        output[y * width + x] = bit == 0 ? 0 : 255;
      }
    }
    return output;
  }
}
