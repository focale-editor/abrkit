import 'package:pscore/pscore.dart';

/// Controls whether recoverable ABR defects stop the complete import.
enum AbrDecodeMode {
  /// Rejects unknown sections and any malformed optional entry.
  strict,

  /// Preserves unknown data and reports recoverable defects as warnings.
  tolerant,
}

/// Resource and compatibility limits applied while decoding an ABR file.
final class AbrDecodeOptions {
  /// Handling policy for recoverable format extensions and damaged entries.
  final AbrDecodeMode mode;

  /// Maximum accepted input size.
  final int maxFileBytes;

  /// Maximum accepted payload size for one modern tagged section.
  final int maxSectionBytes;

  /// Maximum aggregate number of decoded sample and pattern bytes.
  final int maxDecodedPixelBytes;

  /// Maximum width or height accepted for a bitmap.
  final int maxDimension;

  /// Maximum number of decoded brush-tip samples.
  final int maxSamples;

  /// Maximum number of decoded brush presets.
  final int maxBrushes;

  /// Maximum number of decoded embedded patterns.
  final int maxPatterns;

  /// Maximum UTF-16 code-unit count accepted for one embedded pattern name.
  final int maxPatternNameCodeUnits;

  /// Resource limits applied to every decoded Photoshop Action Descriptor.
  final PsDescriptorDecodeOptions descriptorOptions;

  /// Whether tagged-section objects retain complete modern payload bytes.
  final bool preserveSectionData;

  /// Creates bounded decode options suitable for untrusted input.
  const AbrDecodeOptions({
    this.mode = AbrDecodeMode.tolerant,
    this.maxFileBytes = 1024 * 1024 * 1024,
    this.maxSectionBytes = 512 * 1024 * 1024,
    this.maxDecodedPixelBytes = 512 * 1024 * 1024,
    this.maxDimension = 100000,
    this.maxSamples = 100000,
    this.maxBrushes = 100000,
    this.maxPatterns = 10000,
    this.maxPatternNameCodeUnits = 1024 * 1024,
    this.descriptorOptions = const PsDescriptorDecodeOptions(),
    this.preserveSectionData = true,
  });
}

/// Describes a recoverable compatibility issue found while decoding.
final class AbrWarning {
  /// Human-readable explanation of the compatibility issue.
  final String message;

  /// Absolute byte offset associated with the issue, when known.
  final int? offset;

  /// Modern tagged-section key associated with the issue, when known.
  final String? sectionKey;

  /// Creates a warning at an optional absolute byte [offset].
  const AbrWarning({
    required this.message,
    this.offset,
    this.sectionKey,
  });

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    final String section = sectionKey == null ? '' : ' in $sectionKey';
    return 'AbrWarning$location$section: $message';
  }
}

/// Reports malformed, truncated, unsupported, or unsafe ABR input.
final class AbrFormatException implements FormatException {
  /// Human-readable explanation of the malformed data.
  @override
  final String message;

  /// Input associated with the failure, when useful.
  @override
  final Object? source;

  /// Absolute byte offset associated with the failure, when known.
  @override
  final int? offset;

  /// Creates an ABR format error at an optional absolute byte [offset].
  const AbrFormatException({
    required this.message,
    this.source,
    this.offset,
  });

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    return 'AbrFormatException$location: $message';
  }
}
