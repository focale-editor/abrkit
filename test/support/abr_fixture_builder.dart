import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// One modern tagged section used by synthetic ABR tests.
final class AbrTestSection {
  /// Four-byte tagged-section key.
  final String key;

  /// Unpadded section payload.
  final Uint8List data;

  /// Creates a synthetic tagged section.
  const AbrTestSection({
    required this.key,
    required this.data,
  });
}

/// Builds small deterministic ABR buffers covering known structural variants.
abstract final class AbrFixtureBuilder {
  /// Builds one version 1 procedural brush.
  static Uint8List legacyComputed() {
    final PsBinaryWriter record = PsBinaryWriter()
      ..writeUint32(0x12345678)
      ..writeUint16(25)
      ..writeUint16(41)
      ..writeUint16(75)
      ..writeInt16(-30)
      ..writeUint16(60);
    return _legacyFile(version: 1, type: 1, record: record.takeBytes());
  }

  /// Builds one version 2 sampled brush with raw 8-bit opacity.
  static Uint8List legacySampledRaw() {
    final PsBinaryWriter record = PsBinaryWriter()
      ..writeUint32(0)
      ..writeUint16(30);
    _writeUnicodeString(record, 'Éponge');
    record
      ..writeUint8(1)
      ..writeZeros(8)
      ..writeInt32(-1)
      ..writeInt32(-2)
      ..writeInt32(1)
      ..writeInt32(0)
      ..writeUint16(8)
      ..writeUint8(0)
      ..writeBytes(<int>[0, 64, 128, 255]);
    return _legacyFile(version: 2, type: 2, record: record.takeBytes());
  }

  /// Builds one version 1 sampled brush with PackBits-compressed 16-bit opacity.
  static Uint8List legacySampledPackBits16() {
    final Uint8List pixels = Uint8List.fromList(<int>[0x00, 0x00, 0x80, 0x00, 0xff, 0xff, 0x40, 0x00]);
    final PsBinaryWriter record = PsBinaryWriter()
      ..writeUint32(0)
      ..writeUint16(25)
      ..writeUint8(0)
      ..writeZeros(8)
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(2)
      ..writeInt32(2)
      ..writeUint16(16)
      ..writeUint8(1);
    _writePackBitsRows(record, pixels, rowBytes: 4, height: 2);
    return _legacyFile(version: 1, type: 2, record: record.takeBytes());
  }

  /// Builds a two-row 1-bit sample whose rows require byte padding.
  static Uint8List legacySampledBitmap1() {
    final PsBinaryWriter record = PsBinaryWriter()
      ..writeUint32(0)
      ..writeUint16(25)
      ..writeUint8(0)
      ..writeZeros(8)
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(2)
      ..writeInt32(5)
      ..writeUint16(1)
      ..writeUint8(0)
      ..writeBytes(<int>[0xa8, 0x50]);
    return _legacyFile(version: 1, type: 2, record: record.takeBytes());
  }

  /// Builds a modern ABR file from ordered tagged [sections].
  static Uint8List modern({
    required List<AbrTestSection> sections,
    int version = 6,
    int subversion = 2,
    bool padFinalSection = true,
  }) {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint16(version)
      ..writeUint16(subversion);
    for (int index = 0; index < sections.length; index++) {
      final AbrTestSection section = sections[index];
      writer
        ..writeString('8BIM')
        ..writeString(section.key)
        ..writeUint32(section.data.length)
        ..writeBytes(section.data);
      if (padFinalSection || index != sections.length - 1) {
        writer.writeZeros(_padding4(section.data.length));
      }
    }
    return writer.takeBytes();
  }

  /// Builds a `samp` section containing one 2×2 tip.
  static AbrTestSection sampleSection({
    int subversion = 2,
    int depth = 8,
    bool packBits = false,
    String id = 'sample-id',
  }) {
    final Uint8List source = depth == 16 ? Uint8List.fromList(<int>[0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0xff, 0xff]) : Uint8List.fromList(<int>[0, 64, 128, 255]);
    final PsBinaryWriter sample = PsBinaryWriter()
      ..writeUint8(id.length)
      ..writeString(id)
      ..writeZeros(subversion == 1 ? 10 : 264)
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(2)
      ..writeInt32(2)
      ..writeInt16(depth)
      ..writeUint8(packBits ? 1 : 0);
    if (packBits) {
      _writePackBitsRows(sample, source, rowBytes: depth == 16 ? 4 : 2, height: 2);
    } else {
      sample.writeBytes(source);
    }
    final Uint8List sampleBytes = sample.takeBytes();
    final PsBinaryWriter section = PsBinaryWriter()
      ..writeUint32(sampleBytes.length)
      ..writeBytes(sampleBytes)
      ..writeZeros(_padding4(sampleBytes.length));
    return AbrTestSection(key: 'samp', data: section.takeBytes());
  }

  /// Builds a `desc` section with a sampled preset and all major settings groups.
  static AbrTestSection descriptorSection({String sampleId = 'sample-id'}) {
    final PsDescriptor shape = PsDescriptor(
      name: '',
      classId: 'sampledBrush',
      items: <PsDescriptorItem>[
        _item('Nm  ', const PsStringValue(value: 'Test tip\u0000')),
        _item('sampledData', PsStringValue(value: sampleId)),
        _unitItem('Dmtr', '#Pxl', 24),
        _unitItem('Angl', '#Ang', 15),
        _unitItem('Rndn', '#Prc', 80),
        _unitItem('Spcn', '#Prc', 25),
        _item('Intr', const PsBooleanValue(value: true)),
        _item('flipX', const PsBooleanValue(value: false)),
        _item('flipY', const PsBooleanValue(value: true)),
      ],
    );
    final PsDescriptor preset = PsDescriptor(
      name: '',
      classId: 'brushPreset',
      items: <PsDescriptorItem>[
        _item('Nm  ', const PsStringValue(value: 'Synthetic brush\u0000')),
        _objectItem('Brsh', shape),
        _unitItem('Spcn', '#Prc', 25),
        _item('Nose', const PsBooleanValue(value: true)),
        _item('Wtdg', const PsBooleanValue(value: true)),
        _item('Rpt ', const PsBooleanValue(value: true)),
        _item('useBrushSize', const PsBooleanValue(value: true)),
        _item('useTipDynamics', const PsBooleanValue(value: true)),
        _objectItem('szVr', _dynamics(control: 2, jitter: 40, minimum: 10)),
        _objectItem('angleDynamics', _dynamics(control: 6, jitter: 20, minimum: 0)),
        _objectItem('roundnessDynamics', _dynamics(control: 3, jitter: 30, minimum: 15)),
        _unitItem('minimumDiameter', '#Prc', 12),
        _unitItem('minimumRoundness', '#Prc', 20),
        _unitItem('tiltScale', '#Prc', 50),
        _item('flipX', const PsBooleanValue(value: true)),
        _item('flipY', const PsBooleanValue(value: false)),
        _item('brushProjection', const PsBooleanValue(value: true)),
        _item('useScatter', const PsBooleanValue(value: true)),
        _item('bothAxes', const PsBooleanValue(value: true)),
        _item('Cnt ', const PsIntegerValue(value: 3)),
        _objectItem('scatterDynamics', _dynamics(control: 2, jitter: 150, minimum: 0)),
        _objectItem('countDynamics', _dynamics(control: 1, jitter: 50, minimum: 1)),
        _objectItem('dualBrush', PsDescriptor(name: '', classId: 'dualBrush', items: <PsDescriptorItem>[_item('useDualBrush', const PsBooleanValue(value: false))])),
        _item('useTexture', const PsBooleanValue(value: true)),
        _objectItem(
          'Txtr',
          PsDescriptor(
            name: '',
            classId: 'pattern',
            items: <PsDescriptorItem>[
              _item('Nm  ', const PsStringValue(value: 'Paper')),
              _item('Idnt', const PsStringValue(value: 'pattern-id')),
            ],
          ),
        ),
        _item('InvT', const PsBooleanValue(value: true)),
        _unitItem('textureScale', '#Prc', 125),
        _unitItem('textureDepth', '#Prc', 60),
        _unitItem('minimumDepth', '#Prc', 20),
        _objectItem('textureDepthDynamics', _dynamics(control: 2, jitter: 25, minimum: 10)),
        _item('textureBrightness', const PsIntegerValue(value: 5)),
        _item('textureContrast', const PsIntegerValue(value: -3)),
        _item('textureBlendMode', const PsEnumeratedValue(typeId: 'BlnM', value: 'Mltp')),
        _item('TxtC', const PsBooleanValue(value: true)),
        _item('protectTexture', const PsBooleanValue(value: true)),
        _item('useColorDynamics', const PsBooleanValue(value: true)),
        _objectItem('clVr', _dynamics(control: 1, jitter: 35, minimum: 0)),
        _unitItem('H   ', '#Prc', 10),
        _unitItem('Strt', '#Prc', 20),
        _unitItem('Brgh', '#Prc', 30),
        _unitItem('purity', '#Prc', -25),
        _item('colorDynamicsPerTip', const PsBooleanValue(value: true)),
        _item('usePaintDynamics', const PsBooleanValue(value: true)),
        _objectItem('prVr', _dynamics(control: 2, jitter: 15, minimum: 5)),
        _objectItem('opVr', _dynamics(control: 2, jitter: 20, minimum: 10)),
        _objectItem('wtVr', _dynamics(control: 0, jitter: 0, minimum: 0)),
        _objectItem('mxVr', _dynamics(control: 0, jitter: 0, minimum: 0)),
        _item('useBrushPose', const PsBooleanValue(value: true)),
        _item('overridePoseAngle', const PsBooleanValue(value: true)),
        _item('overridePoseTiltX', const PsBooleanValue(value: false)),
        _item('overridePoseTiltY', const PsBooleanValue(value: false)),
        _item('overridePosePressure', const PsBooleanValue(value: true)),
        _unitItem('brushPosePressure', '#Prc', 55),
        _item('brushPoseTiltX', const PsDoubleValue(value: 3)),
        _item('brushPoseTiltY', const PsDoubleValue(value: -4)),
        _item('brushPoseAngle', const PsDoubleValue(value: 45)),
        _objectItem('toolOptions', _toolOptions()),
      ],
    );
    final PsDescriptor root = PsDescriptor(
      name: '',
      classId: 'brushFile',
      items: <PsDescriptorItem>[
        _item('Brsh', PsListValue(values: <PsDescriptorValue>[PsObjectValue(value: preset)])),
      ],
    );
    return AbrTestSection(key: 'desc', data: _versionedDescriptor(root));
  }

  /// Builds a `phry` section with one named hierarchy entry and one empty slot.
  static AbrTestSection hierarchySection() {
    final PsDescriptor entry = PsDescriptor(
      name: '',
      classId: 'brushGroup',
      items: <PsDescriptorItem>[
        _item('Nm  ', const PsStringValue(value: 'Favorites')),
        _item('zuid', const PsStringValue(value: '00000000-0000-0000-0000-000000000001')),
      ],
    );
    final PsDescriptor root = PsDescriptor(
      name: '',
      classId: 'brushHierarchy',
      items: <PsDescriptorItem>[
        _item(
          'hierarchy',
          PsListValue(
            values: <PsDescriptorValue>[
              PsObjectValue(value: entry),
              const PsObjectValue(
                value: PsDescriptor(name: '', classId: 'empty'),
              ),
            ],
          ),
        ),
      ],
    );
    return AbrTestSection(key: 'phry', data: _versionedDescriptor(root));
  }

  /// Builds an RGB `patt` section whose three channels use raw storage.
  static AbrTestSection patternSection() {
    final PsBinaryWriter virtualMemory = PsBinaryWriter()
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(2)
      ..writeInt32(2)
      ..writeUint32(3);
    _writePatternChannel(virtualMemory, <int>[255, 0, 0, 255]);
    _writePatternChannel(virtualMemory, <int>[0, 255, 0, 255]);
    _writePatternChannel(virtualMemory, <int>[0, 0, 255, 255]);
    virtualMemory
      ..writeUint32(0)
      ..writeUint32(0);
    final Uint8List virtualMemoryBytes = virtualMemory.takeBytes();
    final PsBinaryWriter pattern = PsBinaryWriter()
      ..writeUint32(1)
      ..writeUint32(3)
      ..writeInt16(0)
      ..writeInt16(0);
    _writeUnicodeString(pattern, 'Pattern');
    pattern
      ..writeUint8(10)
      ..writeString('pattern-id')
      ..writeUint32(3)
      ..writeUint32(virtualMemoryBytes.length)
      ..writeBytes(virtualMemoryBytes);
    final Uint8List patternBytes = pattern.takeBytes();
    final PsBinaryWriter section = PsBinaryWriter()
      ..writeUint32(patternBytes.length)
      ..writeBytes(patternBytes)
      ..writeZeros(_padding4(patternBytes.length));
    return AbrTestSection(key: 'patt', data: section.takeBytes());
  }

  /// Builds an arbitrary forward-compatible tagged section.
  static AbrTestSection unknownSection() => AbrTestSection(key: 'futr', data: Uint8List.fromList(<int>[1, 2, 3]));

  /// Wraps one fixed-layout record in a complete legacy ABR file.
  static Uint8List _legacyFile({
    required int version,
    required int type,
    required Uint8List record,
  }) =>
      (PsBinaryWriter()
            ..writeUint16(version)
            ..writeUint16(1)
            ..writeUint16(type)
            ..writeUint32(record.length)
            ..writeBytes(record))
          .takeBytes();

  /// Writes independently encoded PackBits rows and their 16-bit lengths.
  static void _writePackBitsRows(PsBinaryWriter writer, Uint8List pixels, {required int rowBytes, required int height}) {
    final List<Uint8List> rows = <Uint8List>[
      for (int row = 0; row < height; row++) PsPackBitsCodec.encodeRow(Uint8List.sublistView(pixels, row * rowBytes, (row + 1) * rowBytes)),
    ];
    for (final Uint8List row in rows) {
      writer.writeUint16(row.length);
    }
    rows.forEach(writer.writeBytes);
  }

  /// Encodes one Action Descriptor with Photoshop's version 16 prefix.
  static Uint8List _versionedDescriptor(PsDescriptor descriptor) =>
      (PsBinaryWriter()
            ..writeUint32(16)
            ..writeBytes(PsDescriptorCodec.encode(descriptor)))
          .takeBytes();

  /// Builds one standard brush-dynamics object.
  static PsDescriptor _dynamics({required int control, required double jitter, required double minimum}) => PsDescriptor(
    name: '',
    classId: 'brVr',
    items: <PsDescriptorItem>[
      _item('bVTy', PsIntegerValue(value: control)),
      _item('fStp', const PsIntegerValue(value: 25)),
      _unitItem('jitter', '#Prc', jitter),
      _unitItem('Mnm ', '#Prc', minimum),
    ],
  );

  /// Builds saved standard brush-tool options.
  static PsDescriptor _toolOptions() => PsDescriptor(
    name: '',
    classId: '_',
    items: <PsDescriptorItem>[
      _item('brushPreset', const PsBooleanValue(value: true)),
      _item('flow', const PsDoubleValue(value: 75)),
      _item('Opct', const PsDoubleValue(value: 80)),
      _item('Smoo', const PsDoubleValue(value: 10)),
      _item('Md  ', const PsEnumeratedValue(typeId: 'BlnM', value: 'Nrml')),
      _item('smoothing', const PsBooleanValue(value: true)),
      _item('smoothingValue', const PsDoubleValue(value: 15)),
      _item('smoothingRadiusMode', const PsBooleanValue(value: true)),
      _item('smoothingCatchup', const PsBooleanValue(value: true)),
      _item('smoothingCatchupAtEnd', const PsBooleanValue(value: false)),
      _item('smoothingZoomCompensation', const PsBooleanValue(value: true)),
      _item('pressureSmoothing', const PsBooleanValue(value: true)),
      _item('usePressureOverridesSize', const PsBooleanValue(value: true)),
      _item('usePressureOverridesOpacity', const PsBooleanValue(value: false)),
      _item('useLegacy', const PsBooleanValue(value: false)),
    ],
  );

  /// Writes one raw 8-bit pattern channel and its virtual-memory header.
  static void _writePatternChannel(PsBinaryWriter writer, List<int> data) {
    final PsBinaryWriter channel = PsBinaryWriter()
      ..writeUint32(8)
      ..writeInt32(0)
      ..writeInt32(0)
      ..writeInt32(2)
      ..writeInt32(2)
      ..writeUint16(8)
      ..writeUint8(0)
      ..writeBytes(data);
    final Uint8List bytes = channel.takeBytes();
    writer
      ..writeUint32(1)
      ..writeUint32(bytes.length)
      ..writeBytes(bytes);
  }

  /// Writes a descriptor-style big-endian UTF-16 string.
  static void _writeUnicodeString(PsBinaryWriter writer, String value) {
    writer.writeUint32(value.codeUnits.length);
    value.codeUnits.forEach(writer.writeUint16);
  }

  /// Creates one descriptor item.
  static PsDescriptorItem _item(String key, PsDescriptorValue value) => PsDescriptorItem(key: key, value: value);

  /// Creates one nested-object descriptor item.
  static PsDescriptorItem _objectItem(String key, PsDescriptor value) => _item(key, PsObjectValue(value: value));

  /// Creates one unit-float descriptor item.
  static PsDescriptorItem _unitItem(String key, String unit, double value) => _item(key, PsUnitFloatValue(unit: unit, value: value));

  /// Returns the padding needed after [length] bytes to reach four-byte alignment.
  static int _padding4(int length) => (4 - length % 4) % 4;
}
