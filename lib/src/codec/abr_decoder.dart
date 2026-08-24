import 'dart:typed_data';

import 'package:abrkit/src/codec/abr_bitmap_decoder.dart';
import 'package:abrkit/src/codec/abr_descriptor_mapper.dart';
import 'package:abrkit/src/codec/abr_pattern_decoder.dart';
import 'package:abrkit/src/model/abr_brush.dart';
import 'package:abrkit/src/model/abr_file.dart';
import 'package:abrkit/src/model/abr_options.dart';
import 'package:abrkit/src/model/abr_pattern.dart';
import 'package:abrkit/src/model/abr_sample.dart';
import 'package:pscore/pscore.dart';

/// Decodes legacy and modern Adobe Photoshop ABR brush libraries.
abstract final class AbrDecoder {
  /// Decodes one complete in-memory ABR [bytes] buffer.
  static AbrFile decode(
    Uint8List bytes, {
    AbrDecodeOptions options = const AbrDecodeOptions(),
  }) {
    if (bytes.length > options.maxFileBytes) {
      throw AbrFormatException(message: 'ABR file size ${bytes.length} exceeds the configured ${options.maxFileBytes} byte limit', source: bytes, offset: 0);
    }
    try {
      return _decode(bytes, options);
    } on AbrFormatException {
      rethrow;
    } on PsFormatException catch (error) {
      throw AbrFormatException(message: error.message, source: bytes, offset: error.offset);
    } on RangeError catch (error) {
      throw AbrFormatException(message: 'Invalid ABR numeric range: $error', source: bytes);
    }
  }

  /// Selects and decodes the structural family identified by the header.
  static AbrFile _decode(Uint8List bytes, AbrDecodeOptions options) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint16();
    final _AbrDecodeContext context = _AbrDecodeContext(
      source: bytes,
      options: options,
      version: version,
    );
    switch (version) {
      case 1:
      case 2:
        _decodeLegacy(reader, context);
      case 6:
      case 7:
      case 9:
      case 10:
        _decodeModern(reader, context);
      default:
        throw PsFormatException(message: 'Unsupported ABR version $version', source: bytes, offset: 0);
    }
    if (!reader.isAtEnd) {
      context.warning('${reader.remaining} trailing bytes remain after the ABR payload', reader.baseOffset + reader.offset);
    }
    context.validateReferences();
    return context.build();
  }

  /// Decodes fixed-layout ABR versions 1 and 2.
  static void _decodeLegacy(PsBinaryReader reader, _AbrDecodeContext context) {
    final int count = reader.readUint16();
    if (count > context.options.maxBrushes) {
      throw PsFormatException(message: 'Legacy brush count $count exceeds the configured ${context.options.maxBrushes} limit', source: reader.bytes, offset: 2);
    }
    for (int index = 0; index < count; index++) {
      final int recordOffset = reader.baseOffset + reader.offset;
      final int type = reader.readUint16();
      final int length = reader.readUint32();
      if (length > reader.remaining) {
        throw PsFormatException(message: 'Legacy brush record length $length exceeds the ${reader.remaining} remaining bytes', source: reader.bytes, offset: recordOffset + 2);
      }
      final PsBinaryReader record = reader.readReader(length);
      try {
        switch (type) {
          case 1:
            _decodeLegacyComputed(record, context, index);
          case 2:
            _decodeLegacySampled(record, context, index);
          default:
            context.warning('Unknown legacy brush type $type was preserved', recordOffset);
            context.addBrush(
              AbrBrush(
                name: 'Unknown brush ${index + 1}',
                shape: AbrUnknownBrushShape(classId: 'legacy:$type', rawData: record.bytes),
                rawData: record.bytes,
              ),
              recordOffset,
            );
        }
      } on Object catch (error) {
        if (context.options.mode == AbrDecodeMode.strict) {
          rethrow;
        }
        context.warning('Legacy brush ${index + 1} could not be decoded and was preserved: $error', recordOffset);
        context.addBrush(
          AbrBrush(
            name: 'Unreadable brush ${index + 1}',
            shape: AbrUnknownBrushShape(classId: 'legacy:$type', rawData: record.bytes),
            rawData: record.bytes,
          ),
          recordOffset,
        );
      }
    }
  }

  /// Decodes a version 1/2 procedural brush record from Adobe's documented layout.
  static void _decodeLegacyComputed(PsBinaryReader record, _AbrDecodeContext context, int index) {
    record.readUint32();
    final int spacing = record.readUint16();
    final int diameter = record.readUint16();
    final int roundness = record.readUint16();
    final int angle = record.readInt16();
    final int hardness = record.readUint16();
    final int trailingOffset = record.baseOffset + record.offset;
    if (!record.isAtEnd) {
      context.warning('${record.remaining} extension bytes remain after legacy computed brush ${index + 1}', trailingOffset);
    }
    context.addBrush(
      AbrBrush(
        name: 'Computed brush ${index + 1}',
        shape: AbrComputedBrushShape(
          diameter: diameter.toDouble(),
          hardness: hardness / 100,
          angle: angle.toDouble(),
          roundness: roundness / 100,
          spacing: spacing / 100,
          spacingEnabled: spacing != 0,
          flipX: false,
          flipY: false,
          rawDescriptor: null,
        ),
        rawData: record.bytes,
      ),
      record.baseOffset,
    );
  }

  /// Decodes a version 1/2 sampled brush and its optional version 2 name.
  static void _decodeLegacySampled(PsBinaryReader record, _AbrDecodeContext context, int index) {
    context.ensureSampleCapacity(record.baseOffset);
    record.readUint32();
    final int spacing = record.readUint16();
    final String? storedName = context.version == 2 ? _readUnicodeString(record, 'legacy brush name') : null;
    final bool antiAliased = record.readUint8() != 0;
    record.skip(8);
    final AbrBounds bounds = _readBounds(record);
    final int depth = record.readUint16();
    final int compressionCode = record.readUint8();
    final AbrCompression compression = AbrCompression.fromCode(compressionCode);
    _validateBitmap(bounds, depth, context, record.baseOffset + record.offset - 19);
    final int retainedBytes = _retainedSampleBytes(bounds, depth);
    context.ensureDecodedBytes(retainedBytes, record.baseOffset);
    final ({Uint8List bytes, Uint16List? samples16}) decoded = AbrBitmapDecoder.decode(
      reader: record,
      width: bounds.width,
      height: bounds.height,
      depth: depth,
      compression: compression,
    );
    final Uint8List alpha = AbrBitmapDecoder.normalizeTo8Bit(
      bytes: decoded.bytes,
      width: bounds.width,
      height: bounds.height,
      depth: depth,
    );
    final Uint8List trailingData = record.readBytes(record.remaining);
    final String id = 'legacy-${index + 1}';
    final String name = _nonEmpty(storedName) ?? 'Sampled brush ${index + 1}';
    context.addSample(
      AbrSample(
        id: id,
        name: storedName,
        bounds: bounds,
        depth: depth,
        compression: compression,
        compressionCode: compressionCode,
        alpha: alpha,
        alpha16: decoded.samples16,
        trailingData: trailingData,
        antiAliased: antiAliased,
      ),
      record.baseOffset,
    );
    context.accountDecodedBytes(retainedBytes, record.baseOffset);
    final double major = bounds.width > bounds.height ? bounds.width.toDouble() : bounds.height.toDouble();
    final double minor = bounds.width < bounds.height ? bounds.width.toDouble() : bounds.height.toDouble();
    context.addBrush(
      AbrBrush(
        name: name,
        shape: AbrSampledBrushShape(
          sampleId: id,
          name: storedName,
          diameter: major,
          angle: 0,
          roundness: minor / major,
          spacing: spacing / 100,
          spacingEnabled: spacing != 0,
          flipX: false,
          flipY: false,
          rawDescriptor: null,
        ),
        rawData: record.bytes,
      ),
      record.baseOffset,
    );
  }

  /// Decodes tagged `8BIM` ABR versions 6, 7, 9, and 10.
  static void _decodeModern(PsBinaryReader reader, _AbrDecodeContext context) {
    final int subversion = reader.readUint16();
    context.subversion = subversion;
    if (subversion != 1 && subversion != 2) {
      context.warning('Unknown ABR subversion $subversion; bitmap samples cannot be interpreted safely', 2);
    }
    while (!reader.isAtEnd) {
      final int sectionOffset = reader.baseOffset + reader.offset;
      if (reader.remaining < 12) {
        context.warning('Truncated modern ABR section header', sectionOffset);
        reader.skip(reader.remaining);
        break;
      }
      final String signature = reader.readString(4);
      final String key = reader.readString(4);
      final int length = reader.readUint32();
      if (length > context.options.maxSectionBytes) {
        throw PsFormatException(message: 'ABR section $key length $length exceeds the configured ${context.options.maxSectionBytes} byte limit', source: reader.bytes, offset: sectionOffset + 8);
      }
      final int paddedLength = _align4(length);
      if (length > reader.remaining) {
        throw PsFormatException(message: 'ABR section $key length $length exceeds the ${reader.remaining} remaining bytes', source: reader.bytes, offset: sectionOffset + 8);
      }
      final PsBinaryReader section = reader.readReader(length);
      _skipOptionalFinalPadding(
        reader: reader,
        padding: paddedLength - length,
        context: context,
        offset: sectionOffset + 12 + length,
        label: 'section $key',
        sectionKey: key,
      );
      context.addSection(
        signature: signature,
        key: key,
        offset: sectionOffset,
        data: section.bytes,
      );
      if (signature != '8BIM') {
        context.warning('Unexpected modern ABR section signature "$signature"', sectionOffset, sectionKey: key);
        continue;
      }
      try {
        _decodeModernSection(section, key, context);
      } on Object catch (error) {
        if (context.options.mode == AbrDecodeMode.strict) {
          rethrow;
        }
        context.warning('Section could not be decoded and was preserved: $error', sectionOffset, sectionKey: key);
      }
    }
  }

  /// Dispatches one bounded modern tagged section.
  static void _decodeModernSection(PsBinaryReader section, String key, _AbrDecodeContext context) {
    switch (key) {
      case 'samp':
        if (context.subversion == 1 || context.subversion == 2) {
          _decodeModernSamples(section, context);
        }
      case 'desc':
        _decodeDescriptorSection(section, context, hierarchy: false);
      case 'patt':
        final List<AbrPattern> decoded = AbrPatternDecoder.decodeAll(
          reader: section,
          options: context.options,
          maxPatterns: context.options.maxPatterns - context.patterns.length,
          onWarning: (message, offset) => context.warning(message, offset, sectionKey: key),
          ensureDecodedBytes: context.ensureDecodedBytes,
          accountDecodedBytes: context.accountDecodedBytes,
        );
        for (final AbrPattern pattern in decoded) {
          context.addPattern(pattern, section.baseOffset);
        }
      case 'phry':
        _decodeDescriptorSection(section, context, hierarchy: true);
      default:
        context.warning('Unknown modern ABR section was preserved', section.baseOffset - 12, sectionKey: key);
    }
  }

  /// Decodes every aligned sampled-tip entry in one `samp` section.
  static void _decodeModernSamples(PsBinaryReader section, _AbrDecodeContext context) {
    while (!section.isAtEnd) {
      final int entryOffset = section.baseOffset + section.offset;
      if (section.remaining < 4) {
        context.warning('Truncated sampled-tip entry length', entryOffset, sectionKey: 'samp');
        section.skip(section.remaining);
        break;
      }
      final int length = section.readUint32();
      final int paddedLength = _align4(length);
      if (length == 0 || length > section.remaining) {
        context.warning('Sampled-tip entry length $length exceeds the section bounds', entryOffset, sectionKey: 'samp');
        section.skip(section.remaining);
        break;
      }
      final PsBinaryReader sample = section.readReader(length);
      _skipOptionalFinalPadding(
        reader: section,
        padding: paddedLength - length,
        context: context,
        offset: entryOffset + 4 + length,
        label: 'sampled-tip entry',
        sectionKey: 'samp',
      );
      try {
        _decodeModernSample(sample, context);
      } on Object catch (error) {
        if (context.options.mode == AbrDecodeMode.strict) {
          rethrow;
        }
        context.warning('Sampled tip could not be decoded and was skipped: $error', entryOffset, sectionKey: 'samp');
      }
    }
  }

  /// Decodes one modern sampled-tip entry for subversion 1 or 2.
  static void _decodeModernSample(PsBinaryReader sample, _AbrDecodeContext context) {
    context.ensureSampleCapacity(sample.baseOffset);
    final String id = _readPascalString(sample);
    final int metadataLength = context.subversion == 1 ? 10 : 264;
    final Uint8List metadata = sample.readBytes(metadataLength);
    final AbrBounds bounds = _readBounds(sample);
    final int depth = sample.readInt16();
    final int compressionCode = sample.readUint8();
    final AbrCompression compression = AbrCompression.fromCode(compressionCode);
    _validateBitmap(bounds, depth, context, sample.baseOffset + sample.offset - 19);
    final int retainedBytes = _retainedSampleBytes(bounds, depth);
    context.ensureDecodedBytes(retainedBytes, sample.baseOffset);
    final ({Uint8List bytes, Uint16List? samples16}) decoded = AbrBitmapDecoder.decode(
      reader: sample,
      width: bounds.width,
      height: bounds.height,
      depth: depth,
      compression: compression,
    );
    final Uint8List alpha = AbrBitmapDecoder.normalizeTo8Bit(
      bytes: decoded.bytes,
      width: bounds.width,
      height: bounds.height,
      depth: depth,
    );
    final Uint8List trailingData = sample.readBytes(sample.remaining);
    context.addSample(
      AbrSample(
        id: id,
        bounds: bounds,
        depth: depth,
        compression: compression,
        compressionCode: compressionCode,
        alpha: alpha,
        alpha16: decoded.samples16,
        metadata: metadata,
        trailingData: trailingData,
      ),
      sample.baseOffset,
    );
    context.accountDecodedBytes(retainedBytes, sample.baseOffset);
  }

  /// Decodes one versioned Action Descriptor from `desc` or `phry`.
  static void _decodeDescriptorSection(PsBinaryReader section, _AbrDecodeContext context, {required bool hierarchy}) {
    final int descriptorVersion = section.readUint32();
    if (descriptorVersion != 16) {
      throw PsFormatException(message: 'Unsupported Action Descriptor version $descriptorVersion', source: section.bytes, offset: section.baseOffset);
    }
    final PsDescriptor descriptor = PsDescriptorCodec.decodeReader(
      section,
      options: context.options.descriptorOptions,
    );
    if (!section.isAtEnd) {
      context.warning(
        '${section.remaining} extension bytes remain after the Action Descriptor',
        section.baseOffset + section.offset,
        sectionKey: hierarchy ? 'phry' : 'desc',
      );
    }
    if (hierarchy) {
      context.hierarchyDescriptors.add(descriptor);
      context.hierarchy.addAll(AbrDescriptorMapper.hierarchy(descriptor));
      return;
    }
    context.descriptors.add(descriptor);
    final List<AbrBrush> brushes = AbrDescriptorMapper.brushes(descriptor);
    for (final AbrBrush brush in brushes) {
      context.addBrush(brush, section.baseOffset);
    }
  }

  /// Reads a top-left-bottom-right rectangle from four signed 32-bit integers.
  static AbrBounds _readBounds(PsBinaryReader reader) => AbrBounds(
    top: reader.readInt32(),
    left: reader.readInt32(),
    bottom: reader.readInt32(),
    right: reader.readInt32(),
  );

  /// Reads a descriptor-style big-endian UTF-16 string.
  static String _readUnicodeString(PsBinaryReader reader, String label) {
    final int length = reader.readUint32();
    if (length > reader.remaining ~/ 2) {
      throw PsFormatException(message: 'Truncated $label', source: reader.bytes, offset: reader.baseOffset + reader.offset);
    }
    final String value = String.fromCharCodes(<int>[
      for (int index = 0; index < length; index++) reader.readUint16(),
    ]);
    return _trimNulls(value);
  }

  /// Reads a one-byte-length Latin-1 string.
  static String _readPascalString(PsBinaryReader reader) => reader.readString(reader.readUint8());

  /// Removes terminal UTF-16 null code units from [value].
  static String _trimNulls(String value) {
    int end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return value.substring(0, end);
  }

  /// Returns [value] only when it contains visible text.
  static String? _nonEmpty(String? value) => value == null || value.isEmpty ? null : value;

  /// Validates sample dimensions and precision before allocating pixel buffers.
  static void _validateBitmap(AbrBounds bounds, int depth, _AbrDecodeContext context, int offset) {
    if (!bounds.isValid || bounds.width > context.options.maxDimension || bounds.height > context.options.maxDimension) {
      throw PsFormatException(message: 'Invalid or excessive sampled-tip bounds ${bounds.width} x ${bounds.height}', source: context.source, offset: offset);
    }
    if (depth != 1 && depth != 8 && depth != 16) {
      throw PsFormatException(message: 'Unsupported sampled-tip depth $depth', source: context.source, offset: offset + 16);
    }
    final int decodedLength = ((bounds.width * depth + 7) ~/ 8) * bounds.height;
    if (decodedLength > context.options.maxDecodedPixelBytes) {
      throw PsFormatException(message: 'Sampled tip requires $decodedLength decoded bytes, exceeding the configured limit', source: context.source, offset: offset);
    }
  }

  /// Returns the bytes retained by one normalized sample model.
  static int _retainedSampleBytes(AbrBounds bounds, int depth) => bounds.pixelCount * (depth == 16 ? 3 : 1);

  /// Skips alignment bytes while accepting an unpadded final payload.
  static void _skipOptionalFinalPadding({
    required PsBinaryReader reader,
    required int padding,
    required _AbrDecodeContext context,
    required int offset,
    required String label,
    required String sectionKey,
  }) {
    if (padding <= reader.remaining) {
      reader.skip(padding);
      return;
    }
    if (reader.isAtEnd) {
      return;
    }
    context.warning('Truncated four-byte padding after $label', offset, sectionKey: sectionKey);
    reader.skip(reader.remaining);
  }

  /// Rounds [value] up to the next four-byte boundary.
  static int _align4(int value) => (value + 3) & ~3;
}

/// Accumulates models, warnings, and resource usage during one decode.
final class _AbrDecodeContext {
  /// Complete source buffer used for normalized exceptions.
  final Uint8List source;

  /// Caller-selected compatibility and allocation limits.
  final AbrDecodeOptions options;

  /// Major ABR version.
  final int version;

  /// Modern ABR subversion assigned after its header is read.
  int? subversion;

  /// Decoded presets in source order.
  final List<AbrBrush> brushes = <AbrBrush>[];

  /// Decoded sampled tips in source order.
  final List<AbrSample> samples = <AbrSample>[];

  /// Decoded embedded patterns in source order.
  final List<AbrPattern> patterns = <AbrPattern>[];

  /// Decoded hierarchy slots in source order.
  final List<AbrHierarchyEntry> hierarchy = <AbrHierarchyEntry>[];

  /// Preserved root preset descriptors.
  final List<PsDescriptor> descriptors = <PsDescriptor>[];

  /// Preserved root hierarchy descriptors.
  final List<PsDescriptor> hierarchyDescriptors = <PsDescriptor>[];

  /// Preserved modern tagged sections.
  final List<AbrTaggedSection> sections = <AbrTaggedSection>[];

  /// Recoverable issues emitted during tolerant decoding.
  final List<AbrWarning> warnings = <AbrWarning>[];

  /// Aggregate decoded bitmap allocation accounted so far.
  int _decodedPixelBytes = 0;

  /// Creates an empty accumulator for one [source] buffer.
  _AbrDecodeContext({
    required this.source,
    required this.options,
    required this.version,
  });

  /// Adds one preset after enforcing the configured count limit.
  void addBrush(AbrBrush brush, int offset) {
    if (brushes.length >= options.maxBrushes) {
      throw PsFormatException(message: 'Brush count exceeds the configured ${options.maxBrushes} limit', source: source, offset: offset);
    }
    brushes.add(brush);
  }

  /// Adds one sampled tip after enforcing the configured count limit.
  void addSample(AbrSample sample, int offset) {
    if (samples.length >= options.maxSamples) {
      throw PsFormatException(message: 'Sample count exceeds the configured ${options.maxSamples} limit', source: source, offset: offset);
    }
    if (samples.any((candidate) => candidate.id == sample.id)) {
      warning('Duplicate sample identifier "${sample.id}"; the last entry wins during lookup', offset, sectionKey: 'samp');
    }
    samples.add(sample);
  }

  /// Checks that another sampled tip can be decoded before allocating it.
  void ensureSampleCapacity(int offset) {
    if (samples.length >= options.maxSamples) {
      throw PsFormatException(message: 'Sample count exceeds the configured ${options.maxSamples} limit', source: source, offset: offset);
    }
  }

  /// Checks aggregate decoded bitmap usage before allocating [bytes].
  void ensureDecodedBytes(int bytes, int offset) {
    if (bytes < 0 || bytes > options.maxDecodedPixelBytes - _decodedPixelBytes) {
      throw PsFormatException(
        message: 'Decoded bitmap data would exceed the configured ${options.maxDecodedPixelBytes} byte limit',
        source: source,
        offset: offset,
      );
    }
  }

  /// Adds one embedded pattern after enforcing the configured count limit.
  void addPattern(AbrPattern pattern, int offset) {
    if (patterns.length >= options.maxPatterns) {
      throw PsFormatException(message: 'Pattern count exceeds the configured ${options.maxPatterns} limit', source: source, offset: offset);
    }
    patterns.add(pattern);
  }

  /// Accounts a decoded bitmap allocation against the aggregate safety limit.
  void accountDecodedBytes(int bytes, int offset) {
    ensureDecodedBytes(bytes, offset);
    _decodedPixelBytes += bytes;
  }

  /// Preserves one modern tagged section according to [options].
  void addSection({
    required String signature,
    required String key,
    required int offset,
    required Uint8List data,
  }) {
    sections.add(
      AbrTaggedSection(
        signature: signature,
        key: key,
        offset: offset,
        data: options.preserveSectionData ? data : Uint8List(0),
      ),
    );
  }

  /// Emits a recoverable warning or converts it to an error in strict mode.
  void warning(
    String message,
    int offset, {
    String? sectionKey,
  }) {
    if (options.mode == AbrDecodeMode.strict) {
      throw PsFormatException(message: message, source: source, offset: offset);
    }
    warnings.add(AbrWarning(message: message, offset: offset, sectionKey: sectionKey));
  }

  /// Reports sampled brush descriptors whose bitmap identifiers are unresolved.
  void validateReferences() {
    final Set<String> sampleIds = <String>{for (final AbrSample sample in samples) sample.id};
    for (final AbrBrush brush in brushes) {
      _validateShapeReference(brush.shape, brush.name, sampleIds);
      final AbrBrushShape? dualShape = brush.settings?.dualBrush?.shape;
      if (dualShape != null) {
        _validateShapeReference(dualShape, '${brush.name} dual brush', sampleIds);
      }
    }
  }

  /// Builds the immutable result after decoding and reference validation.
  AbrFile build() => AbrFile(
    version: version,
    subversion: subversion,
    family: version <= 2 ? AbrFormatFamily.legacy : AbrFormatFamily.modern,
    brushes: brushes,
    samples: samples,
    patterns: patterns,
    hierarchy: hierarchy,
    descriptors: descriptors,
    hierarchyDescriptors: hierarchyDescriptors,
    sections: sections,
    warnings: warnings,
  );

  /// Checks one primary or secondary sampled shape against known sample identifiers.
  void _validateShapeReference(AbrBrushShape shape, String label, Set<String> sampleIds) {
    if (shape is AbrSampledBrushShape && !sampleIds.contains(shape.sampleId)) {
      warning('Brush "$label" references missing sample "${shape.sampleId}"', 0, sectionKey: 'desc');
    }
  }
}
