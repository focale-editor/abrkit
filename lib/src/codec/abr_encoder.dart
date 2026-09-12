import 'dart:convert';
import 'dart:typed_data';

import 'package:abrkit/src/model/abr_brush.dart';
import 'package:abrkit/src/model/abr_file.dart';
import 'package:abrkit/src/model/abr_options.dart';
import 'package:abrkit/src/model/abr_sample.dart';
import 'package:pscore/pscore.dart';

/// Encodes immutable ABR models into legacy or modern Photoshop brush libraries.
///
/// The configured instance is a one-shot [Converter] for complete in-memory
/// files. Use [encode] when conversion options are supplied per call.
final class AbrEncoder extends Converter<AbrFile, List<int>> {
  /// Options applied by [convert].
  final AbrEncodeOptions options;

  /// Creates a reusable encoder with fixed [options].
  const AbrEncoder({
    this.options = const AbrEncodeOptions(),
  });

  @override
  Uint8List convert(AbrFile input) => encode(input, options: options);

  /// Canonical modern section signature.
  static const String _sectionSignature = '8BIM';

  /// Canonical Action Descriptor version.
  static const int _descriptorVersion = 16;

  /// Encodes [file] into a new big-endian ABR byte buffer.
  static Uint8List encode(
    AbrFile file, {
    AbrEncodeOptions options = const AbrEncodeOptions(),
  }) {
    try {
      _validateRepresentable(file, options);
      if (options.mode == AbrEncodeMode.strict) {
        _validateStrict(file, options);
      }
      final PsBinaryWriter writer = PsBinaryWriter()..writeUint16(file.version);
      switch (file.family) {
        case AbrFormatFamily.legacy:
          _writeLegacy(writer, file, options);
        case AbrFormatFamily.modern:
          _writeModern(writer, file, options);
      }
      if (options.includeTrailingData) {
        writer.writeBytes(file.trailingData);
      }
      return writer.takeBytes();
    } on AbrWriteException {
      rethrow;
    } on PsWriteException catch (error) {
      throw AbrWriteException(message: error.message);
    } on RangeError catch (error) {
      throw AbrWriteException(message: 'An ABR numeric value cannot be encoded: $error');
    }
  }

  /// Writes fixed-layout version 1 or 2 brush records.
  static void _writeLegacy(
    PsBinaryWriter writer,
    AbrFile file,
    AbrEncodeOptions options,
  ) {
    writer.writeUint16(file.brushes.length);
    for (int index = 0; index < file.brushes.length; index++) {
      final AbrBrush brush = file.brushes[index];
      final ({int type, Uint8List data}) record = _legacyRecord(file, brush, index, options);
      writer
        ..writeUint16(record.type)
        ..writeUint32(record.data.length)
        ..writeBytes(record.data);
    }
  }

  /// Encodes one known legacy shape or preserves one unknown record.
  static ({int type, Uint8List data}) _legacyRecord(
    AbrFile file,
    AbrBrush brush,
    int index,
    AbrEncodeOptions options,
  ) {
    switch (brush.shape) {
      case final AbrComputedBrushShape shape:
        final PsBinaryWriter data = PsBinaryWriter()
          ..writeUint32(_legacyMiscellaneousValue(brush.rawData))
          ..writeUint16(_percentage(shape.spacingEnabled ? shape.spacing : 0, 'Brush ${index + 1} spacing'))
          ..writeUint16(_roundedUnsigned(shape.diameter, 16, 'Brush ${index + 1} diameter'))
          ..writeUint16(_percentage(shape.roundness, 'Brush ${index + 1} roundness'))
          ..writeInt16(_roundedSigned(shape.angle, 16, 'Brush ${index + 1} angle'))
          ..writeUint16(_percentage(shape.hardness, 'Brush ${index + 1} hardness'));
        final Uint8List? rawData = brush.rawData;
        if (options.mode == AbrEncodeMode.permissive && rawData != null && rawData.length > 14) {
          data.writeBytes(Uint8List.sublistView(rawData, 14));
        }
        return (type: 1, data: data.takeBytes());
      case final AbrSampledBrushShape shape:
        final AbrSample? sample = file.sampleById(shape.sampleId);
        if (sample == null) {
          throw AbrWriteException(message: 'Legacy brush ${index + 1} references missing sample "${shape.sampleId}"');
        }
        final PsBinaryWriter data = PsBinaryWriter()
          ..writeUint32(_legacyMiscellaneousValue(brush.rawData))
          ..writeUint16(_percentage(shape.spacingEnabled ? shape.spacing : 0, 'Brush ${index + 1} spacing'));
        if (file.version == 2) {
          _writeUnicodeString(data, sample.name ?? shape.name ?? brush.name);
        }
        data
          ..writeUint8(sample.antiAliased == true ? 1 : 0)
          ..writeBytes(_legacyReservedData(brush.rawData, file.version))
          ..writeInt32(sample.bounds.top)
          ..writeInt32(sample.bounds.left)
          ..writeInt32(sample.bounds.bottom)
          ..writeInt32(sample.bounds.right)
          ..writeUint16(sample.depth)
          ..writeUint8(sample.compressionCode)
          ..writeBytes(_encodeSamplePixels(sample))
          ..writeBytes(sample.trailingData);
        return (type: 2, data: data.takeBytes());
      case final AbrUnknownBrushShape shape:
        final Uint8List? data = brush.rawData ?? (shape.rawData.isEmpty ? null : shape.rawData);
        if (data == null) {
          throw AbrWriteException(message: 'Unknown legacy brush ${index + 1} has no preserved record payload');
        }
        return (type: _legacyType(shape.classId), data: data);
      case AbrBristleBrushShape() || AbrErodibleBrushShape():
        throw AbrWriteException(message: 'Legacy ABR cannot represent ${brush.shape.runtimeType}');
    }
  }

  /// Writes modern sections while retaining their original relative order where possible.
  static void _writeModern(
    PsBinaryWriter writer,
    AbrFile file,
    AbrEncodeOptions options,
  ) {
    writer.writeUint16(file.subversion ?? 2);
    final Uint8List? sampleData = file.samples.isEmpty ? null : _encodeSamples(file.samples, file.subversion ?? 2);
    final List<PsDescriptor> descriptors = _presetDescriptors(file);
    final Uint8List? patternData = options.includePatterns && file.patterns.isNotEmpty
        ? PsPatternBlockEncoder.encodeAll(
            file.patterns,
            options: PsPatternEncodeOptions(
              mode: options.mode == AbrEncodeMode.strict ? PsPatternEncodeMode.strict : PsPatternEncodeMode.permissive,
              includeVirtualMemoryTrailingData: options.includePatternTrailingData,
              includeRecordTrailingData: options.includePatternTrailingData,
            ),
          )
        : null;
    final List<PsDescriptor> hierarchyDescriptors = options.includeHierarchy ? _hierarchyDescriptors(file) : const <PsDescriptor>[];

    bool samplesWritten = false;
    bool patternsWritten = false;
    int descriptorIndex = 0;
    int hierarchyIndex = 0;
    for (final AbrTaggedSection section in file.sections) {
      final bool canonicalSignature = section.signature == _sectionSignature;
      if (options.mode == AbrEncodeMode.permissive && section.data.length == section.declaredLength) {
        final bool includeSection = switch (section.key) {
          'patt' => options.includePatterns,
          'phry' => options.includeHierarchy,
          'samp' || 'desc' => true,
          _ => options.includeUnknownSections,
        };
        if (includeSection) {
          _writeSection(
            writer,
            section.signature,
            section.key,
            section.data,
            section.paddingData,
            options,
          );
          if (canonicalSignature) {
            switch (section.key) {
              case 'samp':
                samplesWritten = true;
              case 'desc' when descriptorIndex < descriptors.length:
                descriptorIndex++;
              case 'patt':
                patternsWritten = true;
              case 'phry' when hierarchyIndex < hierarchyDescriptors.length:
                hierarchyIndex++;
            }
          }
        }
        continue;
      }
      switch (section.key) {
        case 'samp' when canonicalSignature && samplesWritten:
          continue;
        case 'samp' when canonicalSignature && !samplesWritten && sampleData != null:
          _writeSection(writer, _sectionSignature, section.key, sampleData, section.paddingData, options);
          samplesWritten = true;
        case 'desc' when canonicalSignature && descriptorIndex < descriptors.length:
          _writeSection(
            writer,
            _sectionSignature,
            section.key,
            _encodeDescriptor(descriptors[descriptorIndex++]),
            section.paddingData,
            options,
          );
        case 'patt' when canonicalSignature && !patternsWritten && patternData != null:
          _writeSection(writer, _sectionSignature, section.key, patternData, section.paddingData, options);
          patternsWritten = true;
        case 'patt' when canonicalSignature && patternsWritten:
          continue;
        case 'patt' when !options.includePatterns:
          continue;
        case 'phry' when !options.includeHierarchy:
          continue;
        case 'phry' when canonicalSignature && hierarchyIndex < hierarchyDescriptors.length:
          _writeSection(
            writer,
            _sectionSignature,
            section.key,
            _encodeDescriptor(hierarchyDescriptors[hierarchyIndex++]),
            section.paddingData,
            options,
          );
        default:
          if (_isKnownSection(section.key) || options.includeUnknownSections) {
            final Uint8List data = _preservedSectionData(section);
            _writeSection(writer, section.signature, section.key, data, section.paddingData, options);
          }
      }
    }

    if (!samplesWritten && sampleData != null) {
      _writeSection(writer, _sectionSignature, 'samp', sampleData, Uint8List(0), options);
    }
    while (descriptorIndex < descriptors.length) {
      _writeSection(writer, _sectionSignature, 'desc', _encodeDescriptor(descriptors[descriptorIndex++]), Uint8List(0), options);
    }
    if (!patternsWritten && patternData != null) {
      _writeSection(writer, _sectionSignature, 'patt', patternData, Uint8List(0), options);
    }
    while (hierarchyIndex < hierarchyDescriptors.length) {
      _writeSection(writer, _sectionSignature, 'phry', _encodeDescriptor(hierarchyDescriptors[hierarchyIndex++]), Uint8List(0), options);
    }
  }

  /// Returns source preset descriptors or constructs their root wrapper.
  static List<PsDescriptor> _presetDescriptors(AbrFile file) {
    if (file.descriptors.isNotEmpty) {
      return file.descriptors;
    }
    if (file.brushes.isEmpty) {
      return const <PsDescriptor>[];
    }
    final List<PsDescriptorValue> brushes = <PsDescriptorValue>[];
    for (int index = 0; index < file.brushes.length; index++) {
      final AbrBrush brush = file.brushes[index];
      final PsDescriptor? descriptor = brush.rawDescriptor ?? brush.settings?.rawDescriptor;
      if (descriptor == null) {
        throw AbrWriteException(message: 'Modern brush ${index + 1} has no source descriptor');
      }
      brushes.add(PsObjectValue(value: descriptor));
    }
    return <PsDescriptor>[
      PsDescriptor(
        name: '',
        classId: 'brushFile',
        items: <PsDescriptorItem>[
          PsDescriptorItem(
            key: 'Brsh',
            value: PsListValue(values: brushes),
          ),
        ],
      ),
    ];
  }

  /// Returns source hierarchy descriptors or constructs a root from typed entries.
  static List<PsDescriptor> _hierarchyDescriptors(AbrFile file) {
    if (file.hierarchyDescriptors.isNotEmpty) {
      return file.hierarchyDescriptors;
    }
    if (file.hierarchy.isEmpty) {
      return const <PsDescriptor>[];
    }
    return <PsDescriptor>[
      PsDescriptor(
        name: '',
        classId: 'brushHierarchy',
        items: <PsDescriptorItem>[
          PsDescriptorItem(
            key: 'hierarchy',
            value: PsListValue(
              values: <PsDescriptorValue>[
                for (final AbrHierarchyEntry entry in file.hierarchy)
                  PsObjectValue(
                    value: entry.rawDescriptor ?? const PsDescriptor(name: '', classId: 'empty'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  /// Encodes all sampled-tip entries in one `samp` section payload.
  static Uint8List _encodeSamples(List<AbrSample> samples, int subversion) {
    final PsBinaryWriter section = PsBinaryWriter();
    for (final AbrSample sample in samples) {
      final Uint8List data = _encodeModernSample(sample, subversion);
      section
        ..writeUint32(data.length)
        ..writeBytes(data)
        ..writeZeros((4 - data.length % 4) % 4);
    }
    return section.takeBytes();
  }

  /// Encodes one modern sampled-tip entry.
  static Uint8List _encodeModernSample(AbrSample sample, int subversion) {
    final int metadataLength = subversion == 1 ? 10 : 264;
    final Uint8List metadata = sample.metadata.isEmpty ? Uint8List(metadataLength) : sample.metadata;
    if (metadata.length != metadataLength) {
      throw AbrWriteException(
        message: 'Sample "${sample.id}" metadata has ${metadata.length} bytes; subversion $subversion requires $metadataLength',
      );
    }
    return (PsBinaryWriter()
          ..writeUint8(sample.id.codeUnits.length)
          ..writeString(sample.id)
          ..writeBytes(metadata)
          ..writeInt32(sample.bounds.top)
          ..writeInt32(sample.bounds.left)
          ..writeInt32(sample.bounds.bottom)
          ..writeInt32(sample.bounds.right)
          ..writeInt16(sample.depth)
          ..writeUint8(sample.compressionCode)
          ..writeBytes(_encodeSamplePixels(sample))
          ..writeBytes(sample.trailingData))
        .takeBytes();
  }

  /// Converts normalized or full-precision sample data to the requested storage.
  static Uint8List _encodeSamplePixels(AbrSample sample) {
    final int width = sample.bounds.width;
    final int height = sample.bounds.height;
    final int rowBytes = (width * sample.depth + 7) ~/ 8;
    final Uint8List source = switch (sample.depth) {
      1 => _packBitmap(sample.alpha, width, height),
      8 => Uint8List.fromList(sample.alpha),
      16 => _encode16BitSamples(sample),
      _ => throw AbrWriteException(message: 'Sample "${sample.id}" uses unsupported depth ${sample.depth}'),
    };
    switch (sample.compression) {
      case AbrCompression.raw:
        return source;
      case AbrCompression.packBits:
        final List<Uint8List> rows = <Uint8List>[
          for (int row = 0; row < height; row++)
            PsPackBitsCodec.encodeRow(
              Uint8List.sublistView(source, row * rowBytes, (row + 1) * rowBytes),
            ),
        ];
        final PsBinaryWriter encoded = PsBinaryWriter();
        for (final Uint8List row in rows) {
          if (row.length > 0xffff) {
            throw AbrWriteException(message: 'Sample "${sample.id}" has a PackBits row exceeding the 16-bit length capacity');
          }
          encoded.writeUint16(row.length);
        }
        rows.forEach(encoded.writeBytes);
        return encoded.takeBytes();
      case AbrCompression.unknown:
        throw AbrWriteException(message: 'Sample "${sample.id}" uses unknown compression ${sample.compressionCode}');
    }
  }

  /// Packs expanded opacity bytes into most-significant-bit-first bitmap rows.
  static Uint8List _packBitmap(Uint8List alpha, int width, int height) {
    final int rowBytes = (width + 7) ~/ 8;
    final Uint8List packed = Uint8List(rowBytes * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (alpha[y * width + x] >= 128) {
          packed[y * rowBytes + x ~/ 8] |= 0x80 >> (x % 8);
        }
      }
    }
    return packed;
  }

  /// Converts full-precision or normalized opacity values to big-endian 16-bit samples.
  static Uint8List _encode16BitSamples(AbrSample sample) {
    final int pixelCount = sample.bounds.pixelCount;
    final Uint16List? alpha16 = sample.alpha16;
    final ByteData data = ByteData(pixelCount * 2);
    for (int index = 0; index < pixelCount; index++) {
      data.setUint16(index * 2, alpha16?[index] ?? sample.alpha[index] * 257);
    }
    return data.buffer.asUint8List();
  }

  /// Encodes one versioned Action Descriptor section.
  static Uint8List _encodeDescriptor(PsDescriptor descriptor) =>
      (PsBinaryWriter()
            ..writeUint32(_descriptorVersion)
            ..writeBytes(PsDescriptorCodec.encode(descriptor)))
          .takeBytes();

  /// Writes one modern tagged section and its alignment bytes.
  static void _writeSection(
    PsBinaryWriter writer,
    String signature,
    String key,
    Uint8List data,
    Uint8List preservedPadding,
    AbrEncodeOptions options,
  ) {
    if (options.mode == AbrEncodeMode.strict && signature != _sectionSignature) {
      throw AbrWriteException(message: 'Strict ABR output cannot contain section signature "$signature"');
    }
    writer
      ..writeString(signature)
      ..writeString(key)
      ..writeUint32(data.length)
      ..writeBytes(data);
    if (options.mode == AbrEncodeMode.permissive) {
      writer.writeBytes(preservedPadding);
    } else {
      writer.writeZeros((4 - data.length % 4) % 4);
    }
  }

  /// Returns one complete preserved section payload.
  static Uint8List _preservedSectionData(AbrTaggedSection section) {
    if (section.data.length != section.declaredLength) {
      throw AbrWriteException(
        message: 'Section ${section.key} has only ${section.data.length} of ${section.declaredLength} payload bytes',
      );
    }
    return section.data;
  }

  /// Checks whether [key] has a typed modern representation.
  static bool _isKnownSection(String key) => key == 'samp' || key == 'desc' || key == 'patt' || key == 'phry';

  /// Returns the preserved four-byte miscellaneous field from a legacy record.
  static int _legacyMiscellaneousValue(Uint8List? rawData) {
    if (rawData == null || rawData.length < 4) {
      return 0;
    }
    return ByteData.sublistView(rawData).getUint32(0);
  }

  /// Returns the preserved eight-byte legacy sampled-tip preamble when available.
  static Uint8List _legacyReservedData(Uint8List? rawData, int version) {
    if (rawData == null) {
      return Uint8List(8);
    }
    int offset = 6;
    if (version == 2) {
      if (rawData.length < offset + 4) {
        return Uint8List(8);
      }
      final int length = ByteData.sublistView(rawData).getUint32(offset);
      offset += 4 + length * 2;
    }
    offset++;
    if (offset < 0 || offset + 8 > rawData.length) {
      return Uint8List(8);
    }
    return Uint8List.sublistView(rawData, offset, offset + 8);
  }

  /// Extracts an unknown legacy record type from its synthetic class identifier.
  static int _legacyType(String classId) {
    if (!classId.startsWith('legacy:')) {
      throw AbrWriteException(message: 'Unknown legacy brush class "$classId" does not identify its numeric record type');
    }
    final int? type = int.tryParse(classId.substring('legacy:'.length));
    if (type == null || type < 0 || type > 0xffff) {
      throw AbrWriteException(message: 'Unknown legacy brush class "$classId" has an invalid record type');
    }
    return type;
  }

  /// Writes a descriptor-style UTF-16 string without adding a terminal null.
  static void _writeUnicodeString(PsBinaryWriter writer, String value) {
    writer.writeUint32(value.codeUnits.length);
    value.codeUnits.forEach(writer.writeUint16);
  }

  /// Converts a normalized value to Photoshop's integer percentage scale.
  static int _percentage(double value, String label) => _roundedUnsigned(value * 100, 16, label);

  /// Rounds [value] after checking its unsigned field range.
  static int _roundedUnsigned(double value, int bits, String label) {
    if (!value.isFinite) {
      throw AbrWriteException(message: '$label must be finite');
    }
    final int rounded = value.round();
    final int maximum = (1 << bits) - 1;
    if (rounded < 0 || rounded > maximum) {
      throw AbrWriteException(message: '$label value $value does not fit an unsigned $bits-bit field');
    }
    return rounded;
  }

  /// Rounds [value] after checking its signed field range.
  static int _roundedSigned(double value, int bits, String label) {
    if (!value.isFinite) {
      throw AbrWriteException(message: '$label must be finite');
    }
    final int rounded = value.round();
    final int minimum = -(1 << (bits - 1));
    final int maximum = (1 << (bits - 1)) - 1;
    if (rounded < minimum || rounded > maximum) {
      throw AbrWriteException(message: '$label value $value does not fit a signed $bits-bit field');
    }
    return rounded;
  }

  /// Checks every top-level field and sample buffer before output allocation.
  static void _validateRepresentable(AbrFile file, AbrEncodeOptions options) {
    _requireUnsigned(file.version, 16, 'ABR version');
    if (file.subversion case final int subversion) {
      _requireUnsigned(subversion, 16, 'ABR subversion');
    }
    if (file.family == AbrFormatFamily.legacy && file.brushes.length > 0xffff) {
      throw const AbrWriteException(message: 'Legacy ABR brush count exceeds the 16-bit container capacity');
    }
    final Set<String> sampleIds = <String>{};
    for (final AbrSample sample in file.samples) {
      if (sample.id.codeUnits.length > 0xff || sample.id.codeUnits.any((value) => value > 0xff)) {
        throw AbrWriteException(message: 'Sample identifier "${sample.id}" does not fit a Latin-1 Pascal string');
      }
      _requireSigned(sample.bounds.top, 32, 'Sample ${sample.id} top bound');
      _requireSigned(sample.bounds.left, 32, 'Sample ${sample.id} left bound');
      _requireSigned(sample.bounds.bottom, 32, 'Sample ${sample.id} bottom bound');
      _requireSigned(sample.bounds.right, 32, 'Sample ${sample.id} right bound');
      _requireUnsigned(sample.depth, 16, 'Sample ${sample.id} depth');
      _requireUnsigned(sample.compressionCode, 8, 'Sample ${sample.id} compression');
      if (!sample.bounds.isValid || sample.alpha.length != sample.bounds.pixelCount) {
        throw AbrWriteException(message: 'Sample "${sample.id}" dimensions do not match its ${sample.alpha.length} opacity bytes');
      }
      if (sample.alpha16 != null && sample.alpha16!.length != sample.bounds.pixelCount) {
        throw AbrWriteException(message: 'Sample "${sample.id}" dimensions do not match its 16-bit opacity values');
      }
      if (!sampleIds.add(sample.id) && options.mode == AbrEncodeMode.strict) {
        throw AbrWriteException(message: 'Strict ABR output cannot contain duplicate sample identifier "${sample.id}"');
      }
    }
    for (final AbrTaggedSection section in file.sections) {
      _requireLatin1(section.signature, 4, 'ABR section signature');
      _requireLatin1(section.key, 4, 'ABR section key');
      _requireUnsigned(section.declaredLength, 32, 'ABR section ${section.key} declared length');
    }
    if (options.includeTrailingData && file.trailingData.length != file.trailingByteCount) {
      throw AbrWriteException(
        message: 'Only ${file.trailingData.length} of ${file.trailingByteCount} trailing bytes were preserved; disable trailing-data output or decode with preservation enabled',
      );
    }
  }

  /// Applies constraints for supported legacy and modern output families.
  static void _validateStrict(AbrFile file, AbrEncodeOptions options) {
    switch (file.family) {
      case AbrFormatFamily.legacy:
        if (file.version != 1 && file.version != 2 || file.subversion != null) {
          throw const AbrWriteException(message: 'Strict legacy ABR output requires major version 1 or 2 and no subversion');
        }
        if (file.sections.isNotEmpty || file.descriptors.isNotEmpty || file.hierarchyDescriptors.isNotEmpty || file.patterns.isNotEmpty) {
          throw const AbrWriteException(message: 'Legacy ABR output cannot contain modern sections, descriptors, or patterns');
        }
      case AbrFormatFamily.modern:
        if (file.version != 6 && file.version != 7 && file.version != 9 && file.version != 10) {
          throw AbrWriteException(message: 'Strict modern ABR output does not support major version ${file.version}');
        }
        if (file.subversion != 1 && file.subversion != 2) {
          throw AbrWriteException(message: 'Strict modern ABR output does not support subversion ${file.subversion}');
        }
        for (final AbrTaggedSection section in file.sections) {
          if (section.signature != _sectionSignature && (_isKnownSection(section.key) || options.includeUnknownSections)) {
            throw AbrWriteException(message: 'Strict ABR output cannot contain section signature "${section.signature}"');
          }
        }
    }
    for (final AbrSample sample in file.samples) {
      if (sample.id.isEmpty || sample.depth != 1 && sample.depth != 8 && sample.depth != 16) {
        throw AbrWriteException(message: 'Sample "${sample.id}" has no identifier or uses unsupported depth ${sample.depth}');
      }
      if (sample.compression == AbrCompression.unknown || sample.compression.code != sample.compressionCode) {
        throw AbrWriteException(message: 'Sample "${sample.id}" uses unsupported compression ${sample.compressionCode}');
      }
    }
    if (options.includeTrailingData && file.trailingData.isNotEmpty) {
      throw const AbrWriteException(message: 'Strict ABR output cannot contain unrecognized trailing bytes');
    }
  }

  /// Requires [value] to fit an unsigned integer field.
  static void _requireUnsigned(int value, int bits, String label) {
    final int maximum = (1 << bits) - 1;
    if (value < 0 || value > maximum) {
      throw AbrWriteException(message: '$label value $value does not fit an unsigned $bits-bit field');
    }
  }

  /// Requires [value] to fit a signed integer field.
  static void _requireSigned(int value, int bits, String label) {
    final int minimum = -(1 << (bits - 1));
    final int maximum = (1 << (bits - 1)) - 1;
    if (value < minimum || value > maximum) {
      throw AbrWriteException(message: '$label value $value does not fit a signed $bits-bit field');
    }
  }

  /// Requires [value] to contain exactly [length] one-byte characters.
  static void _requireLatin1(String value, int length, String label) {
    if (value.length != length || value.codeUnits.any((codeUnit) => codeUnit > 0xff)) {
      throw AbrWriteException(message: '$label must contain exactly $length Latin-1 bytes');
    }
  }
}
