import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Input source selected for one Photoshop brush dynamic.
enum AbrDynamicsControl {
  /// No input modulation.
  off(code: 0),

  /// Linear fade across a configured number of steps.
  fade(code: 1),

  /// Stylus pressure.
  penPressure(code: 2),

  /// Stylus tilt.
  penTilt(code: 3),

  /// Stylus barrel wheel.
  stylusWheel(code: 4),

  /// Direction at the beginning of a stroke.
  initialDirection(code: 5),

  /// Current stroke direction.
  direction(code: 6),

  /// Stylus rotation at the beginning of a stroke.
  initialRotation(code: 7),

  /// Current stylus rotation.
  rotation(code: 8),

  /// A source code unknown to this release.
  unknown(code: -1);

  /// Numeric Action Descriptor value.
  final int code;

  /// Creates a dynamic control with its descriptor [code].
  const AbrDynamicsControl({required this.code});

  /// Resolves an Action Descriptor control [code].
  static AbrDynamicsControl fromCode(int code) => switch (code) {
    0 => off,
    1 => fade,
    2 => penPressure,
    3 => penTilt,
    4 => stylusWheel,
    5 => initialDirection,
    6 => direction,
    7 => initialRotation,
    8 => rotation,
    _ => unknown,
  };
}

/// Jitter, lower bound, and input source for one brush property.
final class AbrDynamics {
  /// Known interpretation of [controlCode].
  final AbrDynamicsControl control;

  /// Original numeric input-source code.
  final int controlCode;

  /// Fade duration when [control] is [AbrDynamicsControl.fade].
  final int fadeSteps;

  /// Normalized jitter, where `1` represents 100 percent.
  final double jitter;

  /// Normalized minimum output, where `1` represents 100 percent.
  final double minimum;

  /// Complete dynamics object for lossless access to extension fields.
  final PsDescriptor rawDescriptor;

  /// Creates decoded dynamics while retaining their source descriptor.
  const AbrDynamics({
    required this.control,
    required this.controlCode,
    required this.fadeSteps,
    required this.jitter,
    required this.minimum,
    required this.rawDescriptor,
  });
}

/// Base type for the brush-tip shapes represented by ABR presets.
sealed class AbrBrushShape {
  /// Creates a brush-tip shape.
  const AbrBrushShape();

  /// Complete source descriptor, or `null` for legacy fixed-layout records.
  PsDescriptor? get rawDescriptor;
}

/// A procedural hard- or soft-edged elliptical brush tip.
final class AbrComputedBrushShape extends AbrBrushShape {
  /// Diameter in pixels.
  final double diameter;

  /// Normalized edge hardness.
  final double hardness;

  /// Clockwise tip angle in degrees.
  final double angle;

  /// Normalized minor-to-major diameter ratio.
  final double roundness;

  /// Normalized distance between successive dabs.
  final double spacing;

  /// Whether explicit dab spacing is enabled.
  final bool spacingEnabled;

  /// Whether the tip is mirrored horizontally.
  final bool flipX;

  /// Whether the tip is mirrored vertically.
  final bool flipY;

  /// Complete source descriptor, or `null` for legacy records.
  @override
  final PsDescriptor? rawDescriptor;

  /// Creates a procedural shape.
  const AbrComputedBrushShape({
    required this.diameter,
    required this.hardness,
    required this.angle,
    required this.roundness,
    required this.spacing,
    required this.spacingEnabled,
    required this.flipX,
    required this.flipY,
    required this.rawDescriptor,
  });
}

/// A brush tip backed by one grayscale sample from the ABR file.
final class AbrSampledBrushShape extends AbrBrushShape {
  /// Identifier of the corresponding `samp` entry.
  final String sampleId;

  /// Optional shape name independent from the preset name.
  final String? name;

  /// Diameter in pixels.
  final double diameter;

  /// Clockwise tip angle in degrees.
  final double angle;

  /// Normalized minor-to-major diameter ratio.
  final double roundness;

  /// Normalized distance between successive dabs.
  final double spacing;

  /// Whether explicit dab spacing is enabled.
  final bool spacingEnabled;

  /// Whether the tip is mirrored horizontally.
  final bool flipX;

  /// Whether the tip is mirrored vertically.
  final bool flipY;

  /// Complete source descriptor, or `null` for legacy records.
  @override
  final PsDescriptor? rawDescriptor;

  /// Creates a sampled shape.
  const AbrSampledBrushShape({
    required this.sampleId,
    required this.diameter,
    required this.angle,
    required this.roundness,
    required this.spacing,
    required this.spacingEnabled,
    required this.flipX,
    required this.flipY,
    required this.rawDescriptor,
    this.name,
  });
}

/// Cross-section used by Photoshop's bristle and erodible brush engines.
enum AbrBristleShape {
  /// Rounded point.
  roundPoint,

  /// Rounded blunt end.
  roundBlunt,

  /// Rounded curved end.
  roundCurve,

  /// Rounded angled end.
  roundAngle,

  /// Rounded fan.
  roundFan,

  /// Flat point.
  flatPoint,

  /// Flat blunt end.
  flatBlunt,

  /// Flat curved end.
  flatCurve,

  /// Flat angled end.
  flatAngle,

  /// Flat fan.
  flatFan,

  /// A shape index unknown to this release.
  unknown,
}

/// A physically simulated bristle brush tip.
final class AbrBristleBrushShape extends AbrBrushShape {
  /// Known cross-section interpretation.
  final AbrBristleShape shape;

  /// Original numeric cross-section code.
  final int shapeCode;

  /// Diameter in pixels.
  final double diameter;

  /// Clockwise tip angle in degrees.
  final double angle;

  /// Normalized bristle density.
  final double density;

  /// Normalized bristle length.
  final double length;

  /// Normalized bristle clumping.
  final double clumping;

  /// Normalized bristle thickness.
  final double thickness;

  /// Normalized bristle stiffness.
  final double stiffness;

  /// Whether physical simulation is enabled.
  final bool physics;

  /// Normalized distance between successive dabs.
  final double spacing;

  /// Whether explicit dab spacing is enabled.
  final bool spacingEnabled;

  /// Whether the tip is mirrored horizontally.
  final bool flipX;

  /// Whether the tip is mirrored vertically.
  final bool flipY;

  /// Complete source descriptor for this bristle shape.
  @override
  final PsDescriptor rawDescriptor;

  /// Creates a decoded bristle shape.
  const AbrBristleBrushShape({
    required this.shape,
    required this.shapeCode,
    required this.diameter,
    required this.angle,
    required this.density,
    required this.length,
    required this.clumping,
    required this.thickness,
    required this.stiffness,
    required this.physics,
    required this.spacing,
    required this.spacingEnabled,
    required this.flipX,
    required this.flipY,
    required this.rawDescriptor,
  });
}

/// Erodible or airbrush-tip family selected by Photoshop's `dTips` engine.
enum AbrErodibleTipType {
  /// Erodible pointed tip.
  point,

  /// Erodible flat tip.
  flat,

  /// Erodible round tip.
  round,

  /// Erodible square tip.
  square,

  /// Erodible triangular tip.
  triangle,

  /// A custom height-map tip.
  custom,

  /// A tip index unknown to this release.
  unknown,
}

/// An erodible, custom-height-map, or airbrush tip.
final class AbrErodibleBrushShape extends AbrBrushShape {
  /// Known erodible-tip interpretation.
  final AbrErodibleTipType tipType;

  /// Original numeric erodible-tip code.
  final int tipTypeCode;

  /// Known brush cross-section interpretation.
  final AbrBristleShape shape;

  /// Original numeric cross-section code.
  final int shapeCode;

  /// Diameter in pixels.
  final double diameter;

  /// Clockwise tip angle in degrees.
  final double angle;

  /// Normalized length-to-width ratio.
  final double lengthRatio;

  /// Normalized erodible-tip hardness.
  final double hardness;

  /// Optional height-map side length.
  final int? gridSize;

  /// Preserved custom height-map bytes.
  final Uint8List heightMap;

  /// Whether physical simulation is enabled.
  final bool physics;

  /// Normalized distance between successive dabs.
  final double spacing;

  /// Whether explicit dab spacing is enabled.
  final bool spacingEnabled;

  /// Whether the tip is mirrored horizontally.
  final bool flipX;

  /// Whether the tip is mirrored vertically.
  final bool flipY;

  /// Airbrush cone cutoff angle.
  final double airbrushCutoffAngle;

  /// Normalized airbrush granularity.
  final double airbrushGranularity;

  /// Normalized airbrush streakiness.
  final double airbrushStreakiness;

  /// Normalized airbrush splat size.
  final double airbrushSplatSize;

  /// Airbrush splat count.
  final int airbrushSplatCount;

  /// Complete source descriptor for this erodible shape.
  @override
  final PsDescriptor rawDescriptor;

  /// Creates a decoded erodible or airbrush shape.
  AbrErodibleBrushShape({
    required this.tipType,
    required this.tipTypeCode,
    required this.shape,
    required this.shapeCode,
    required this.diameter,
    required this.angle,
    required this.lengthRatio,
    required this.hardness,
    required this.physics,
    required this.spacing,
    required this.spacingEnabled,
    required this.flipX,
    required this.flipY,
    required this.airbrushCutoffAngle,
    required this.airbrushGranularity,
    required this.airbrushStreakiness,
    required this.airbrushSplatSize,
    required this.airbrushSplatCount,
    required this.rawDescriptor,
    required Uint8List heightMap,
    this.gridSize,
  }) : heightMap = Uint8List.fromList(heightMap).asUnmodifiableView();
}

/// A descriptor-defined brush shape whose class is not yet understood.
final class AbrUnknownBrushShape extends AbrBrushShape {
  /// Photoshop descriptor class identifier.
  final String classId;

  /// Complete source descriptor when this is a modern unknown shape.
  @override
  final PsDescriptor? rawDescriptor;

  /// Preserved fixed-layout payload for an unknown legacy record.
  final Uint8List rawData;

  /// Creates a forward-compatible unknown shape.
  AbrUnknownBrushShape({
    required this.classId,
    this.rawDescriptor,
    Uint8List? rawData,
  }) : rawData = Uint8List.fromList(rawData ?? Uint8List(0)).asUnmodifiableView();
}

/// Tip-size, angle, and roundness modulation settings.
final class AbrShapeDynamicsSettings {
  /// Tip-size modulation.
  final AbrDynamics size;

  /// Tip-angle modulation.
  final AbrDynamics angle;

  /// Tip-roundness modulation.
  final AbrDynamics roundness;

  /// Normalized lower bound for the diameter.
  final double minimumDiameter;

  /// Normalized lower bound for roundness.
  final double minimumRoundness;

  /// Normalized tilt scaling.
  final double tiltScale;

  /// Whether random horizontal flipping is enabled.
  final bool flipX;

  /// Whether random vertical flipping is enabled.
  final bool flipY;

  /// Whether the tip is projected along the stroke.
  final bool projectToStroke;

  /// Creates decoded shape dynamics.
  const AbrShapeDynamicsSettings({
    required this.size,
    required this.angle,
    required this.roundness,
    required this.minimumDiameter,
    required this.minimumRoundness,
    required this.tiltScale,
    required this.flipX,
    required this.flipY,
    required this.projectToStroke,
  });
}

/// Brush-tip scattering and count settings.
final class AbrScatterSettings {
  /// Whether scattering applies perpendicular and parallel to the stroke.
  final bool bothAxes;

  /// Number of tip instances per spacing interval.
  final int count;

  /// Scatter-distance modulation.
  final AbrDynamics scatter;

  /// Tip-count modulation.
  final AbrDynamics countDynamics;

  /// Creates decoded scattering settings.
  const AbrScatterSettings({
    required this.bothAxes,
    required this.count,
    required this.scatter,
    required this.countDynamics,
  });
}

/// Pattern texture settings attached to a brush preset.
final class AbrTextureSettings {
  /// Identifier of the embedded or externally installed pattern.
  final String patternId;

  /// Human-readable pattern name.
  final String patternName;

  /// Whether the pattern luminance is inverted.
  final bool invert;

  /// Normalized texture scale.
  final double scale;

  /// Signed Photoshop brightness adjustment.
  final int brightness;

  /// Signed Photoshop contrast adjustment.
  final int contrast;

  /// Photoshop blend-mode identifier.
  final String blendMode;

  /// Normalized texture depth.
  final double depth;

  /// Normalized minimum texture depth.
  final double minimumDepth;

  /// Texture-depth modulation.
  final AbrDynamics depthDynamics;

  /// Whether texture is recalculated for every tip.
  final bool eachTip;

  /// Creates decoded texture settings.
  const AbrTextureSettings({
    required this.patternId,
    required this.patternName,
    required this.invert,
    required this.scale,
    required this.brightness,
    required this.contrast,
    required this.blendMode,
    required this.depth,
    required this.minimumDepth,
    required this.depthDynamics,
    required this.eachTip,
  });
}

/// Secondary-tip settings used by Photoshop's dual-brush engine.
final class AbrDualBrushSettings {
  /// Whether the secondary tip is flipped.
  final bool flip;

  /// Secondary brush-tip shape.
  final AbrBrushShape shape;

  /// Photoshop blend-mode identifier.
  final String blendMode;

  /// Whether secondary-tip scattering is enabled.
  final bool scatterEnabled;

  /// Normalized secondary-tip spacing.
  final double spacing;

  /// Number of secondary tips per interval.
  final int count;

  /// Whether secondary scattering applies on both axes.
  final bool bothAxes;

  /// Secondary-tip count modulation.
  final AbrDynamics countDynamics;

  /// Secondary-tip scattering modulation.
  final AbrDynamics scatterDynamics;

  /// Creates decoded dual-brush settings.
  const AbrDualBrushSettings({
    required this.flip,
    required this.shape,
    required this.blendMode,
    required this.scatterEnabled,
    required this.spacing,
    required this.count,
    required this.bothAxes,
    required this.countDynamics,
    required this.scatterDynamics,
  });
}

/// Foreground/background and color-jitter settings.
final class AbrColorDynamicsSettings {
  /// Foreground-to-background modulation.
  final AbrDynamics foregroundBackground;

  /// Normalized hue jitter.
  final double hue;

  /// Normalized saturation jitter.
  final double saturation;

  /// Normalized brightness jitter.
  final double brightness;

  /// Normalized color-purity adjustment.
  final double purity;

  /// Whether jitter is applied independently to each tip.
  final bool perTip;

  /// Creates decoded color dynamics.
  const AbrColorDynamicsSettings({
    required this.foregroundBackground,
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.purity,
    required this.perTip,
  });
}

/// Opacity, flow, wetness, and mix modulation settings.
final class AbrTransferSettings {
  /// Flow modulation.
  final AbrDynamics flow;

  /// Opacity modulation.
  final AbrDynamics opacity;

  /// Mixer wetness modulation.
  final AbrDynamics wetness;

  /// Mixer paint-mix modulation.
  final AbrDynamics mix;

  /// Creates decoded transfer settings.
  const AbrTransferSettings({
    required this.flow,
    required this.opacity,
    required this.wetness,
    required this.mix,
  });
}

/// Explicit stylus pose and per-component override settings.
final class AbrBrushPoseSettings {
  /// Whether [angle] overrides live stylus input.
  final bool overrideAngle;

  /// Whether [tiltX] overrides live stylus input.
  final bool overrideTiltX;

  /// Whether [tiltY] overrides live stylus input.
  final bool overrideTiltY;

  /// Whether [pressure] overrides live stylus input.
  final bool overridePressure;

  /// Normalized pressure value.
  final double pressure;

  /// Horizontal tilt value in Photoshop units.
  final double tiltX;

  /// Vertical tilt value in Photoshop units.
  final double tiltY;

  /// Barrel angle in Photoshop units.
  final double angle;

  /// Creates decoded brush-pose settings.
  const AbrBrushPoseSettings({
    required this.overrideAngle,
    required this.overrideTiltX,
    required this.overrideTiltY,
    required this.overridePressure,
    required this.pressure,
    required this.tiltX,
    required this.tiltY,
    required this.angle,
  });
}

/// Photoshop tool associated with a brush preset.
enum AbrToolType {
  /// Standard paint brush.
  brush,

  /// Mixer brush.
  mixerBrush,

  /// Smudge tool.
  smudgeBrush,

  /// Eraser tool.
  eraser,

  /// Pencil or another brush-like tool.
  other,
}

/// Tool-level options saved alongside a brush preset.
final class AbrToolOptions {
  /// Known tool family.
  final AbrToolType type;

  /// Original Photoshop tool class identifier.
  final String classId;

  /// Whether the tool explicitly references the enclosing preset.
  final bool brushPreset;

  /// Flow percentage in Photoshop's 0–100 scale.
  final double flow;

  /// Opacity percentage in Photoshop's 0–100 scale.
  final double opacity;

  /// Legacy smoothness value.
  final double smooth;

  /// Photoshop blend-mode identifier.
  final String blendMode;

  /// Whether stroke smoothing is enabled.
  final bool smoothing;

  /// Smoothing amount in Photoshop's stored scale.
  final double smoothingValue;

  /// Whether smoothing uses radius mode.
  final bool smoothingRadiusMode;

  /// Whether the stroke catches up to the pointer.
  final bool smoothingCatchUp;

  /// Whether catch-up completes at stroke end.
  final bool smoothingCatchUpAtEnd;

  /// Whether smoothing compensates for zoom.
  final bool smoothingZoomCompensation;

  /// Whether pressure values are smoothed.
  final bool pressureSmoothing;

  /// Whether pressure overrides the preset's size dynamic.
  final bool pressureOverridesSize;

  /// Whether pressure overrides the preset's opacity dynamic.
  final bool pressureOverridesOpacity;

  /// Whether Photoshop's legacy brush behavior is requested.
  final bool legacy;

  /// Mixer wetness percentage, when applicable.
  final double? wetness;

  /// Mixer dryness percentage, when applicable.
  final double? dryness;

  /// Mixer paint-mix percentage, when applicable.
  final double? mix;

  /// Whether the mixer reservoir is refilled automatically.
  final bool? autoFill;

  /// Whether the mixer brush is cleaned automatically.
  final bool? autoClean;

  /// Whether only a solid color is loaded.
  final bool? loadSolidColorOnly;

  /// Whether paint is sampled from every visible layer.
  final bool? sampleAllLayers;

  /// Tool-level flow modulation.
  final AbrDynamics? flowDynamics;

  /// Tool-level opacity modulation.
  final AbrDynamics? opacityDynamics;

  /// Tool-level size modulation.
  final AbrDynamics? sizeDynamics;

  /// Whether smudging paints with the current foreground color.
  final bool? smudgeFingerPainting;

  /// Whether smudging samples all visible layers.
  final bool? smudgeSampleAllLayers;

  /// Smudge strength percentage, when applicable.
  final double? strength;

  /// Complete source object for lossless access to extension fields.
  final PsDescriptor rawDescriptor;

  /// Creates decoded tool options.
  const AbrToolOptions({
    required this.type,
    required this.classId,
    required this.brushPreset,
    required this.flow,
    required this.opacity,
    required this.smooth,
    required this.blendMode,
    required this.smoothing,
    required this.smoothingValue,
    required this.smoothingRadiusMode,
    required this.smoothingCatchUp,
    required this.smoothingCatchUpAtEnd,
    required this.smoothingZoomCompensation,
    required this.pressureSmoothing,
    required this.pressureOverridesSize,
    required this.pressureOverridesOpacity,
    required this.legacy,
    required this.rawDescriptor,
    this.wetness,
    this.dryness,
    this.mix,
    this.autoFill,
    this.autoClean,
    this.loadSolidColorOnly,
    this.sampleAllLayers,
    this.flowDynamics,
    this.opacityDynamics,
    this.sizeDynamics,
    this.smudgeFingerPainting,
    this.smudgeSampleAllLayers,
    this.strength,
  });
}

/// Complete decoded behavior attached to one modern brush preset.
final class AbrBrushSettings {
  /// Normalized top-level spacing value.
  final double spacing;

  /// Whether texture noise is enabled.
  final bool noise;

  /// Whether wet-edge darkening is enabled.
  final bool wetEdges;

  /// Whether paint accumulates while the pointer is stationary.
  final bool buildUp;

  /// Whether the saved preset applies its brush size.
  final bool useBrushSize;

  /// Shape-dynamics settings, when enabled.
  final AbrShapeDynamicsSettings? shapeDynamics;

  /// Scattering settings, when enabled.
  final AbrScatterSettings? scatter;

  /// Texture settings, when enabled.
  final AbrTextureSettings? texture;

  /// Secondary-tip settings, when enabled.
  final AbrDualBrushSettings? dualBrush;

  /// Color-dynamics settings, when enabled.
  final AbrColorDynamicsSettings? colorDynamics;

  /// Paint-transfer settings, when enabled.
  final AbrTransferSettings? transfer;

  /// Saved brush-pose settings, when enabled.
  final AbrBrushPoseSettings? pose;

  /// Tool-level settings saved with the preset.
  final AbrToolOptions? toolOptions;

  /// Whether Photoshop protects the texture across compatible presets.
  final bool? protectTexture;

  /// Undocumented texture interpretation flag, when present.
  final bool? interpretation;

  /// Complete preset descriptor for lossless access to known and future fields.
  final PsDescriptor rawDescriptor;

  /// Creates decoded brush behavior while retaining the complete descriptor.
  const AbrBrushSettings({
    required this.spacing,
    required this.noise,
    required this.wetEdges,
    required this.buildUp,
    required this.useBrushSize,
    required this.rawDescriptor,
    this.shapeDynamics,
    this.scatter,
    this.texture,
    this.dualBrush,
    this.colorDynamics,
    this.transfer,
    this.pose,
    this.toolOptions,
    this.protectTexture,
    this.interpretation,
  });
}

/// One named brush preset from an ABR library.
final class AbrBrush {
  /// Human-readable preset name.
  final String name;

  /// Brush-tip geometry or sampled-image reference.
  final AbrBrushShape shape;

  /// Modern behavioral settings, or `null` for legacy fixed-layout brushes.
  final AbrBrushSettings? settings;

  /// Complete modern preset object, or `null` for legacy records.
  final PsDescriptor? rawDescriptor;

  /// Complete legacy record payload, or `null` for modern descriptor presets.
  final Uint8List? rawData;

  /// Creates a decoded brush preset.
  AbrBrush({
    required this.name,
    required this.shape,
    this.settings,
    this.rawDescriptor,
    Uint8List? rawData,
  }) : rawData = rawData == null ? null : Uint8List.fromList(rawData).asUnmodifiableView();
}
