import 'dart:typed_data';

import 'package:abrkit/src/model/abr_brush.dart';
import 'package:abrkit/src/model/abr_file.dart';
import 'package:pscore/pscore.dart';

/// Converts generic Photoshop Action Descriptors into typed ABR domain models.
abstract final class AbrDescriptorMapper {
  /// Decodes every preset object stored under the root `Brsh` list.
  static List<AbrBrush> brushes(PsDescriptor root) {
    final _DescriptorView rootView = _DescriptorView(descriptor: root);
    final List<PsDescriptor> descriptors = rootView.objects('Brsh');
    return <AbrBrush>[
      for (final PsDescriptor descriptor in descriptors) _brush(descriptor),
    ];
  }

  /// Decodes every object or empty slot stored under the root `hierarchy` list.
  static List<AbrHierarchyEntry> hierarchy(PsDescriptor root) {
    final PsDescriptorValue? value = root.value('hierarchy');
    if (value is! PsListValue) {
      return const <AbrHierarchyEntry>[];
    }
    final List<AbrHierarchyEntry> entries = <AbrHierarchyEntry>[];
    for (int index = 0; index < value.values.length; index++) {
      final PsDescriptorValue item = value.values[index];
      final PsDescriptor? descriptor = switch (item) {
        PsObjectValue(:final PsDescriptor value) => value,
        _ => null,
      };
      final _DescriptorView? view = descriptor == null ? null : _DescriptorView(descriptor: descriptor);
      entries.add(
        AbrHierarchyEntry(
          index: index,
          name: view?.string('Nm  '),
          id: view?.string('zuid'),
          rawDescriptor: descriptor,
        ),
      );
    }
    return entries;
  }

  /// Decodes one brush-preset descriptor.
  static AbrBrush _brush(PsDescriptor descriptor) {
    final _DescriptorView view = _DescriptorView(descriptor: descriptor);
    final PsDescriptor shapeDescriptor = view.object('Brsh') ?? const PsDescriptor(name: '', classId: 'missingBrushShape');
    return AbrBrush(
      name: view.string('Nm  ') ?? '',
      shape: _shape(shapeDescriptor),
      settings: _settings(view),
      rawDescriptor: descriptor,
    );
  }

  /// Decodes the descriptor class used for a primary or dual brush tip.
  static AbrBrushShape _shape(PsDescriptor descriptor) {
    final _DescriptorView view = _DescriptorView(descriptor: descriptor);
    return switch (descriptor.classId) {
      'computedBrush' => AbrComputedBrushShape(
        diameter: view.number('Dmtr'),
        hardness: view.percent('Hrdn'),
        angle: view.number('Angl'),
        roundness: view.percent('Rndn'),
        spacing: view.percent('Spcn'),
        spacingEnabled: view.boolean('Intr'),
        flipX: view.boolean('flipX'),
        flipY: view.boolean('flipY'),
        rawDescriptor: descriptor,
      ),
      'sampledBrush' => AbrSampledBrushShape(
        sampleId: view.string('sampledData') ?? '',
        name: view.string('Nm  '),
        diameter: view.number('Dmtr'),
        angle: view.number('Angl'),
        roundness: view.percent('Rndn'),
        spacing: view.percent('Spcn'),
        spacingEnabled: view.boolean('Intr'),
        flipX: view.boolean('flipX'),
        flipY: view.boolean('flipY'),
        rawDescriptor: descriptor,
      ),
      'dBrush' => _bristleShape(view),
      'dTips' => _erodibleShape(view),
      _ => AbrUnknownBrushShape(classId: descriptor.classId, rawDescriptor: descriptor),
    };
  }

  /// Decodes Photoshop's physically simulated `dBrush` shape.
  static AbrBristleBrushShape _bristleShape(_DescriptorView view) {
    final int shapeCode = view.integer('Shp ');
    return AbrBristleBrushShape(
      shape: _bristleShapeForCode(shapeCode),
      shapeCode: shapeCode,
      diameter: view.number('Dmtr'),
      angle: view.number('Angl'),
      density: view.percent('Dnst'),
      length: view.percent('Lngt'),
      clumping: view.percent('clumping'),
      thickness: view.percent('thickness'),
      stiffness: view.percent('stiffness'),
      physics: view.boolean('physics'),
      spacing: view.percent('Spcn'),
      spacingEnabled: view.boolean('Intr'),
      flipX: view.boolean('flipX'),
      flipY: view.boolean('flipY'),
      rawDescriptor: view.descriptor,
    );
  }

  /// Decodes Photoshop's erodible, height-map, and airbrush `dTips` shape.
  static AbrErodibleBrushShape _erodibleShape(_DescriptorView view) {
    final int tipTypeCode = view.integer('dtipsType');
    final int shapeCode = view.integer('Shp ');
    return AbrErodibleBrushShape(
      tipType: _erodibleTypeForCode(tipTypeCode),
      tipTypeCode: tipTypeCode,
      shape: _bristleShapeForCode(shapeCode),
      shapeCode: shapeCode,
      diameter: view.number('Dmtr'),
      angle: view.number('Angl'),
      lengthRatio: view.percent('dtipsLengthRatio'),
      hardness: view.percent('dtipsHardness'),
      gridSize: view.nullableInteger('dtipsGridSize'),
      heightMap: view.bytes('dtipsErodibleTipHeightMap') ?? Uint8List(0),
      physics: view.boolean('physics'),
      spacing: view.percent('Spcn'),
      spacingEnabled: view.boolean('Intr'),
      flipX: view.boolean('flipX'),
      flipY: view.boolean('flipY'),
      airbrushCutoffAngle: view.number('dtipsAirbrushCutoffAngle'),
      airbrushGranularity: view.percent('dtipsAirbrushGranularity'),
      airbrushStreakiness: view.percent('dtipsAirbrushStreakiness'),
      airbrushSplatSize: view.percent('dtipsAirbrushSplatSize'),
      airbrushSplatCount: view.integer('dtipsAirbrushSplatCount'),
      rawDescriptor: view.descriptor,
    );
  }

  /// Decodes all behavioral groups stored in a preset descriptor.
  static AbrBrushSettings _settings(_DescriptorView view) => AbrBrushSettings(
    spacing: view.percent('Spcn'),
    noise: view.boolean('Nose'),
    wetEdges: view.boolean('Wtdg'),
    buildUp: view.boolean('Rpt '),
    useBrushSize: view.boolean('useBrushSize', fallback: true),
    shapeDynamics: view.boolean('useTipDynamics') ? _shapeDynamics(view) : null,
    scatter: view.boolean('useScatter') ? _scatter(view) : null,
    texture: view.boolean('useTexture') ? _texture(view) : null,
    dualBrush: _dualBrush(view),
    colorDynamics: view.boolean('useColorDynamics') ? _colorDynamics(view) : null,
    transfer: view.boolean('usePaintDynamics') ? _transfer(view) : null,
    pose: view.boolean('useBrushPose') ? _pose(view) : null,
    toolOptions: _toolOptions(view.object('toolOptions')),
    protectTexture: view.nullableBoolean('protectTexture'),
    interpretation: view.nullableBoolean('interpretation'),
    rawDescriptor: view.descriptor,
  );

  /// Decodes shape dynamics from their sibling preset keys.
  static AbrShapeDynamicsSettings _shapeDynamics(_DescriptorView view) => AbrShapeDynamicsSettings(
    size: _dynamics(view.object('szVr')),
    angle: _dynamics(view.object('angleDynamics')),
    roundness: _dynamics(view.object('roundnessDynamics')),
    minimumDiameter: view.percent('minimumDiameter'),
    minimumRoundness: view.percent('minimumRoundness'),
    tiltScale: view.percent('tiltScale'),
    flipX: view.boolean('flipX'),
    flipY: view.boolean('flipY'),
    projectToStroke: view.boolean('brushProjection'),
  );

  /// Decodes top-level scatter and count dynamics.
  static AbrScatterSettings _scatter(_DescriptorView view) => AbrScatterSettings(
    bothAxes: view.boolean('bothAxes'),
    count: view.integer('Cnt ', fallback: 1),
    scatter: _dynamics(view.object('scatterDynamics')),
    countDynamics: _dynamics(view.object('countDynamics')),
  );

  /// Decodes an optional texture pattern and its depth modulation.
  static AbrTextureSettings? _texture(_DescriptorView view) {
    final PsDescriptor? pattern = view.object('Txtr');
    if (pattern == null) {
      return null;
    }
    final _DescriptorView patternView = _DescriptorView(descriptor: pattern);
    return AbrTextureSettings(
      patternId: patternView.string('Idnt') ?? '',
      patternName: patternView.string('Nm  ') ?? '',
      invert: view.boolean('InvT'),
      scale: view.percent('textureScale', fallback: 1),
      brightness: view.integer('textureBrightness'),
      contrast: view.integer('textureContrast'),
      blendMode: view.enumeration('textureBlendMode') ?? '',
      depth: view.percent('textureDepth', fallback: 1),
      minimumDepth: view.percent('minimumDepth'),
      depthDynamics: _dynamics(view.object('textureDepthDynamics')),
      eachTip: view.boolean('TxtC'),
    );
  }

  /// Decodes the optional secondary-tip descriptor.
  static AbrDualBrushSettings? _dualBrush(_DescriptorView view) {
    final PsDescriptor? descriptor = view.object('dualBrush');
    if (descriptor == null) {
      return null;
    }
    final _DescriptorView dual = _DescriptorView(descriptor: descriptor);
    if (!dual.boolean('useDualBrush')) {
      return null;
    }
    final PsDescriptor shape = dual.object('Brsh') ?? const PsDescriptor(name: '', classId: 'missingDualBrushShape');
    return AbrDualBrushSettings(
      flip: dual.boolean('Flip'),
      shape: _shape(shape),
      blendMode: dual.enumeration('BlnM') ?? '',
      scatterEnabled: dual.boolean('useScatter'),
      spacing: dual.percent('Spcn'),
      count: dual.integer('Cnt ', fallback: 1),
      bothAxes: dual.boolean('bothAxes'),
      countDynamics: _dynamics(dual.object('countDynamics')),
      scatterDynamics: _dynamics(dual.object('scatterDynamics')),
    );
  }

  /// Decodes foreground/background and color jitter.
  static AbrColorDynamicsSettings _colorDynamics(_DescriptorView view) => AbrColorDynamicsSettings(
    foregroundBackground: _dynamics(view.object('clVr')),
    hue: view.percent('H   '),
    saturation: view.percent('Strt'),
    brightness: view.percent('Brgh'),
    purity: view.percent('purity'),
    perTip: view.boolean('colorDynamicsPerTip'),
  );

  /// Decodes flow, opacity, wetness, and mix modulation.
  static AbrTransferSettings _transfer(_DescriptorView view) => AbrTransferSettings(
    flow: _dynamics(view.object('prVr')),
    opacity: _dynamics(view.object('opVr')),
    wetness: _dynamics(view.object('wtVr')),
    mix: _dynamics(view.object('mxVr')),
  );

  /// Decodes a saved synthetic stylus pose.
  static AbrBrushPoseSettings _pose(_DescriptorView view) => AbrBrushPoseSettings(
    overrideAngle: view.boolean('overridePoseAngle'),
    overrideTiltX: view.boolean('overridePoseTiltX'),
    overrideTiltY: view.boolean('overridePoseTiltY'),
    overridePressure: view.boolean('overridePosePressure'),
    pressure: view.percent('brushPosePressure'),
    tiltX: view.number('brushPoseTiltX'),
    tiltY: view.number('brushPoseTiltY'),
    angle: view.number('brushPoseAngle'),
  );

  /// Decodes one dynamics object or an empty disabled object when absent.
  static AbrDynamics _dynamics(PsDescriptor? descriptor) {
    final PsDescriptor value = descriptor ?? const PsDescriptor(name: '', classId: 'nullDynamics');
    final _DescriptorView view = _DescriptorView(descriptor: value);
    final int controlCode = view.integer('bVTy');
    return AbrDynamics(
      control: AbrDynamicsControl.fromCode(controlCode),
      controlCode: controlCode,
      fadeSteps: view.integer('fStp'),
      jitter: view.percent('jitter'),
      minimum: view.percent('Mnm '),
      rawDescriptor: value,
    );
  }

  /// Decodes optional tool settings saved alongside a brush preset.
  static AbrToolOptions? _toolOptions(PsDescriptor? descriptor) {
    if (descriptor == null) {
      return null;
    }
    final _DescriptorView view = _DescriptorView(descriptor: descriptor);
    return AbrToolOptions(
      type: _toolType(descriptor.classId),
      classId: descriptor.classId,
      brushPreset: view.boolean('brushPreset'),
      flow: view.number('flow', fallback: 100),
      opacity: view.number('Opct', fallback: 100),
      smooth: view.number('Smoo'),
      blendMode: view.enumeration('Md  ') ?? 'Nrml',
      smoothing: view.boolean('smoothing'),
      smoothingValue: view.number('smoothingValue'),
      smoothingRadiusMode: view.boolean('smoothingRadiusMode'),
      smoothingCatchUp: view.boolean('smoothingCatchup'),
      smoothingCatchUpAtEnd: view.boolean('smoothingCatchupAtEnd'),
      smoothingZoomCompensation: view.boolean('smoothingZoomCompensation'),
      pressureSmoothing: view.boolean('pressureSmoothing'),
      pressureOverridesSize: view.boolean('usePressureOverridesSize'),
      pressureOverridesOpacity: view.boolean('usePressureOverridesOpacity'),
      legacy: view.boolean('useLegacy'),
      wetness: view.nullableNumber('wetness'),
      dryness: view.nullableNumber('dryness'),
      mix: view.nullableNumber('mix'),
      autoFill: view.nullableBoolean('autoFill'),
      autoClean: view.nullableBoolean('autoClean'),
      loadSolidColorOnly: view.nullableBoolean('loadSolidColorOnly'),
      sampleAllLayers: view.nullableBoolean('sampleAllLayers'),
      flowDynamics: _nullableDynamics(view.object('prVr')),
      opacityDynamics: _nullableDynamics(view.object('opVr')),
      sizeDynamics: _nullableDynamics(view.object('szVr')),
      smudgeFingerPainting: view.nullableBoolean('SmdF'),
      smudgeSampleAllLayers: view.nullableBoolean('SmdS'),
      strength: view.nullableNumber('Prs '),
      rawDescriptor: descriptor,
    );
  }

  /// Decodes [descriptor] only when it exists.
  static AbrDynamics? _nullableDynamics(PsDescriptor? descriptor) => descriptor == null ? null : _dynamics(descriptor);

  /// Maps a bristle shape index while preserving unknown codes elsewhere.
  static AbrBristleShape _bristleShapeForCode(int code) => switch (code) {
    0 => AbrBristleShape.roundPoint,
    1 => AbrBristleShape.roundBlunt,
    2 => AbrBristleShape.roundCurve,
    3 => AbrBristleShape.roundAngle,
    4 => AbrBristleShape.roundFan,
    5 => AbrBristleShape.flatPoint,
    6 => AbrBristleShape.flatBlunt,
    7 => AbrBristleShape.flatCurve,
    8 => AbrBristleShape.flatAngle,
    9 => AbrBristleShape.flatFan,
    _ => AbrBristleShape.unknown,
  };

  /// Maps an erodible-tip index while preserving unknown codes elsewhere.
  static AbrErodibleTipType _erodibleTypeForCode(int code) => switch (code) {
    0 => AbrErodibleTipType.point,
    1 => AbrErodibleTipType.flat,
    2 => AbrErodibleTipType.round,
    3 => AbrErodibleTipType.square,
    4 => AbrErodibleTipType.triangle,
    5 => AbrErodibleTipType.custom,
    _ => AbrErodibleTipType.unknown,
  };

  /// Maps known Photoshop tool class identifiers.
  static AbrToolType _toolType(String classId) => switch (classId) {
    '_' => AbrToolType.brush,
    'MixB' => AbrToolType.mixerBrush,
    'SmTl' => AbrToolType.smudgeBrush,
    'ErTl' => AbrToolType.eraser,
    _ => AbrToolType.other,
  };
}

/// Provides null-safe typed access to one generic Action Descriptor.
final class _DescriptorView {
  /// Descriptor exposed through the typed accessors.
  final PsDescriptor descriptor;

  /// Creates a typed view over [descriptor].
  const _DescriptorView({
    required this.descriptor,
  });

  /// Returns an object descriptor stored under [key].
  PsDescriptor? object(String key) => switch (descriptor.value(key)) {
    PsObjectValue(:final PsDescriptor value) => value,
    _ => null,
  };

  /// Returns all object descriptors in a list or a single object under [key].
  List<PsDescriptor> objects(String key) => switch (descriptor.value(key)) {
    PsListValue(:final List<PsDescriptorValue> values) => <PsDescriptor>[
      for (final PsDescriptorValue value in values)
        if (value case PsObjectValue(:final PsDescriptor value)) value,
    ],
    PsObjectValue(:final PsDescriptor value) => <PsDescriptor>[value],
    _ => const <PsDescriptor>[],
  };

  /// Returns a Boolean under [key] or [fallback].
  bool boolean(
    String key, {
    bool fallback = false,
  }) => nullableBoolean(key) ?? fallback;

  /// Returns a Boolean under [key], if its descriptor type is compatible.
  bool? nullableBoolean(String key) => switch (descriptor.value(key)) {
    PsBooleanValue(:final bool value) => value,
    PsIntegerValue(:final int value) => value != 0,
    _ => null,
  };

  /// Returns an integer under [key] or [fallback].
  int integer(
    String key, {
    int fallback = 0,
  }) => nullableInteger(key) ?? fallback;

  /// Returns an integer under [key], if its descriptor type is compatible.
  int? nullableInteger(String key) => switch (descriptor.value(key)) {
    PsIntegerValue(:final int value) => value,
    PsLargeIntegerValue(:final int value) => value,
    PsDoubleValue(:final double value) => value.round(),
    PsUnitFloatValue(:final double value) => value.round(),
    _ => null,
  };

  /// Returns a numeric value under [key] or [fallback].
  double number(
    String key, {
    double fallback = 0,
  }) => nullableNumber(key) ?? fallback;

  /// Returns a numeric value under [key], ignoring an optional unit code.
  double? nullableNumber(String key) => switch (descriptor.value(key)) {
    PsIntegerValue(:final int value) => value.toDouble(),
    PsLargeIntegerValue(:final int value) => value.toDouble(),
    PsDoubleValue(:final double value) => value,
    PsUnitFloatValue(:final double value) => value,
    _ => null,
  };

  /// Returns a normalized percentage under [key] or [fallback].
  double percent(
    String key, {
    double fallback = 0,
  }) {
    final PsDescriptorValue? value = descriptor.value(key);
    return switch (value) {
      PsUnitFloatValue(unit: '#Prc', :final double value) => value / 100,
      PsUnitFloatValue(:final double value) => value,
      PsDoubleValue(:final double value) => value,
      PsIntegerValue(:final int value) => value.toDouble(),
      _ => fallback,
    };
  }

  /// Returns a string under [key] with trailing UTF-16 nulls removed.
  String? string(String key) => switch (descriptor.value(key)) {
    PsStringValue(:final String value) => _trimNulls(value),
    _ => null,
  };

  /// Returns the selected enumeration identifier under [key].
  String? enumeration(String key) => switch (descriptor.value(key)) {
    PsEnumeratedValue(:final String value) => value,
    PsStringValue(:final String value) => _trimNulls(value),
    _ => null,
  };

  /// Returns preserved byte data under [key].
  Uint8List? bytes(String key) => switch (descriptor.value(key)) {
    PsRawValue(:final Uint8List value) => value,
    PsAliasValue(:final Uint8List value) => value,
    PsPathValue(:final Uint8List value) => value,
    _ => null,
  };

  /// Removes only terminal null code units used by Photoshop strings.
  static String _trimNulls(String value) {
    int end = value.length;
    while (end > 0 && value.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return value.substring(0, end);
  }
}
