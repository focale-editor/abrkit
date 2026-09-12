import 'package:pscore/pscore.dart';

/// Controls whether recoverable ABR defects stop the complete import.
enum AbrDecodeMode {
  /// Rejects unknown sections and any malformed optional entry.
  strict,

  /// Preserves unknown data and reports recoverable defects as warnings.
  tolerant,
}

/// Controls how strongly an ABR library is validated before encoding.
enum AbrEncodeMode {
  /// Produces a canonical library using the supported ABR structures.
  strict,

  /// Writes representable preserved values, including compatibility extensions.
  permissive,
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

  /// Whether bytes after the recognized ABR payload are retained.
  final bool preserveTrailingData;

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
    this.preserveTrailingData = true,
  });
}

/// Preservation and validation choices applied while encoding an ABR library.
final class AbrEncodeOptions {
  /// Validation policy applied before values are written.
  final AbrEncodeMode mode;

  /// Whether unrecognized modern tagged sections are retained.
  final bool includeUnknownSections;

  /// Whether embedded texture-pattern sections are written.
  final bool includePatterns;

  /// Whether brush hierarchy sections are written.
  final bool includeHierarchy;

  /// Whether bytes after the recognized ABR payload are appended.
  final bool includeTrailingData;

  /// Whether extension bytes inside embedded patterns are retained.
  final bool includePatternTrailingData;

  /// Creates encoding options for canonical ABR output by default.
  const AbrEncodeOptions({
    this.mode = AbrEncodeMode.strict,
    this.includeUnknownSections = true,
    this.includePatterns = true,
    this.includeHierarchy = true,
    this.includeTrailingData = true,
    this.includePatternTrailingData = true,
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

/// Reports model data that cannot be represented by the requested ABR output.
final class AbrWriteException implements Exception {
  /// Explains why encoding failed.
  final String message;

  /// Creates an encoding error with a user-facing [message].
  const AbrWriteException({
    required this.message,
  });

  @override
  String toString() => 'AbrWriteException: $message';
}
