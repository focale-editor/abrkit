import 'package:abrkit/src/model/abr_options.dart';
import 'package:abrkit/src/model/abr_pattern.dart';
import 'package:pscore/pscore.dart';

/// Decodes the versioned Photoshop pattern records embedded in `patt` sections.
abstract final class AbrPatternDecoder {
  /// Decodes every length-prefixed pattern in [reader].
  static List<AbrPattern> decodeAll({
    required PsBinaryReader reader,
    required AbrDecodeOptions options,
    required int maxPatterns,
    required void Function(String message, int offset) onWarning,
    required void Function(int bytes, int offset) ensureDecodedBytes,
    required void Function(int bytes, int offset) accountDecodedBytes,
  }) {
    /// Reports a compatibility issue or promotes it in strict mode.
    void issue(String message, int offset) {
      if (options.mode == AbrDecodeMode.strict) {
        throw PsFormatException(message: message, source: reader.bytes, offset: offset);
      }
      onWarning(message, offset);
    }

    final PsPatternBlockDecodeResult result = PsPatternBlockDecoder.decodeAll(
      reader: reader,
      maxPatterns: maxPatterns,
      options: PsPatternDecodeOptions(
        maxDimension: options.maxDimension,
        maxChannelCount: 1024,
        maxNameCodeUnits: options.maxPatternNameCodeUnits,
        maxDecodedBytes: options.maxDecodedPixelBytes,
        preserveChannelData: options.preserveSectionData,
        preserveRecordData: options.preserveSectionData,
      ),
      onIssue: issue,
      onDecodedBytesRequired: ensureDecodedBytes,
    );
    accountDecodedBytes(result.decodedBytes, reader.baseOffset);
    return result.patterns;
  }
}
