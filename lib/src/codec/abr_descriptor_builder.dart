import 'package:abrkit/src/model/abr_brush.dart';
import 'package:abrkit/src/model/abr_file.dart';
import 'package:abrkit/src/model/abr_options.dart';
import 'package:pscore/pscore.dart';

/// Synthesizes canonical Action Descriptors for newly created ABR brushes.
abstract final class AbrDescriptorBuilder {
  /// Builds a minimal modern preset descriptor from one typed [brush] in [file].
  static PsDescriptor preset(AbrFile file, AbrBrush brush, int index) {
    if (brush.shape case AbrSampledBrushShape(:final String sampleId) when file.sampleById(sampleId) == null) {
      throw AbrWriteException(message: 'Modern brush ${index + 1} references missing sample "$sampleId"');
    }
    final PsDescriptor shapeDescriptor = _shapeDescriptor(brush.shape, index);
    final double spacing = switch (brush.shape) {
      AbrComputedBrushShape(:final double spacing) ||
      AbrSampledBrushShape(:final double spacing) ||
      AbrBristleBrushShape(:final double spacing) ||
      AbrErodibleBrushShape(:final double spacing) => spacing,
      AbrUnknownBrushShape() => 0.25,
    };
    _requireNonNegative(spacing, 'Modern brush ${index + 1} spacing');
    return PsDescriptor(
      name: '',
      classId: 'brushPreset',
      items: [
        PsDescriptorItem(
          key: 'Nm  ',
          value: PsStringValue(value: _terminatedPhotoshopString(brush.name)),
        ),
        PsDescriptorItem(
          key: 'Brsh',
          value: PsObjectValue(value: shapeDescriptor),
        ),
        PsDescriptorItem(
          key: 'Spcn',
          value: PsUnitFloatValue(unit: '#Prc', value: spacing * 100),
        ),
        const PsDescriptorItem(
          key: 'Nose',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'Wtdg',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'Rpt ',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'useBrushSize',
          value: PsBooleanValue(value: true),
        ),
        const PsDescriptorItem(
          key: 'useTipDynamics',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'useScatter',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'useTexture',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'useColorDynamics',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'usePaintDynamics',
          value: PsBooleanValue(value: false),
        ),
        const PsDescriptorItem(
          key: 'useBrushPose',
          value: PsBooleanValue(value: false),
        ),
      ],
    );
  }

  /// Builds a modern tip descriptor when no preserved descriptor is available.
  static PsDescriptor _shapeDescriptor(AbrBrushShape shape, int index) {
    final PsDescriptor? rawDescriptor = shape.rawDescriptor;
    if (rawDescriptor != null) {
      return rawDescriptor;
    }
    return switch (shape) {
      final AbrComputedBrushShape computed => _computedShapeDescriptor(computed, index),
      final AbrSampledBrushShape sampled => _sampledShapeDescriptor(sampled, index),
      AbrBristleBrushShape() ||
      AbrErodibleBrushShape() ||
      AbrUnknownBrushShape() => throw AbrWriteException(message: 'Modern brush ${index + 1} cannot synthesize a descriptor for ${shape.runtimeType}'),
    };
  }

  /// Builds the canonical descriptor for one typed computed tip.
  static PsDescriptor _computedShapeDescriptor(AbrComputedBrushShape shape, int index) {
    _validateBasicShape(
      diameter: shape.diameter,
      angle: shape.angle,
      roundness: shape.roundness,
      spacing: shape.spacing,
      label: 'Modern brush ${index + 1}',
    );
    _requireNormalized(shape.hardness, 'Modern brush ${index + 1} hardness');
    return PsDescriptor(
      name: '',
      classId: 'computedBrush',
      items: [
        PsDescriptorItem(
          key: 'Dmtr',
          value: PsUnitFloatValue(unit: '#Pxl', value: shape.diameter),
        ),
        PsDescriptorItem(
          key: 'Hrdn',
          value: PsUnitFloatValue(unit: '#Prc', value: shape.hardness * 100),
        ),
        PsDescriptorItem(
          key: 'Angl',
          value: PsUnitFloatValue(unit: '#Ang', value: shape.angle),
        ),
        PsDescriptorItem(
          key: 'Rndn',
          value: PsUnitFloatValue(unit: '#Prc', value: shape.roundness * 100),
        ),
        PsDescriptorItem(
          key: 'Spcn',
          value: PsUnitFloatValue(unit: '#Prc', value: shape.spacing * 100),
        ),
        PsDescriptorItem(
          key: 'Intr',
          value: PsBooleanValue(value: shape.spacingEnabled),
        ),
        PsDescriptorItem(
          key: 'flipX',
          value: PsBooleanValue(value: shape.flipX),
        ),
        PsDescriptorItem(
          key: 'flipY',
          value: PsBooleanValue(value: shape.flipY),
        ),
      ],
    );
  }

  /// Builds the canonical descriptor for one typed sampled tip.
  static PsDescriptor _sampledShapeDescriptor(AbrSampledBrushShape shape, int index) {
    _validateBasicShape(
      diameter: shape.diameter,
      angle: shape.angle,
      roundness: shape.roundness,
      spacing: shape.spacing,
      label: 'Modern brush ${index + 1}',
    );
    return PsDescriptor(
      name: '',
      classId: 'sampledBrush',
      items: [
        if (shape.name case final String name)
          PsDescriptorItem(
            key: 'Nm  ',
            value: PsStringValue(value: _terminatedPhotoshopString(name)),
          ),
        PsDescriptorItem(
          key: 'sampledData',
          value: PsStringValue(value: shape.sampleId),
        ),
        PsDescriptorItem(
          key: 'Dmtr',
          value: PsUnitFloatValue(unit: '#Pxl', value: shape.diameter),
        ),
        PsDescriptorItem(
          key: 'Angl',
          value: PsUnitFloatValue(unit: '#Ang', value: shape.angle),
        ),
        PsDescriptorItem(
          key: 'Rndn',
          value: PsUnitFloatValue(unit: '#Prc', value: shape.roundness * 100),
        ),
        PsDescriptorItem(
          key: 'Spcn',
          value: PsUnitFloatValue(unit: '#Prc', value: shape.spacing * 100),
        ),
        PsDescriptorItem(
          key: 'Intr',
          value: PsBooleanValue(value: shape.spacingEnabled),
        ),
        PsDescriptorItem(
          key: 'flipX',
          value: PsBooleanValue(value: shape.flipX),
        ),
        PsDescriptorItem(
          key: 'flipY',
          value: PsBooleanValue(value: shape.flipY),
        ),
      ],
    );
  }

  /// Validates geometry shared by computed and sampled modern tips.
  static void _validateBasicShape({
    required double diameter,
    required double angle,
    required double roundness,
    required double spacing,
    required String label,
  }) {
    if (!diameter.isFinite || diameter <= 0) {
      throw AbrWriteException(message: '$label diameter must be finite and greater than zero');
    }
    if (!angle.isFinite) {
      throw AbrWriteException(message: '$label angle must be finite');
    }
    _requireNormalized(roundness, '$label roundness');
    _requireNonNegative(spacing, '$label spacing');
  }

  /// Requires one finite [value] in the inclusive normalized range.
  static void _requireNormalized(double value, String label) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw AbrWriteException(message: '$label must be finite and between zero and one');
    }
  }

  /// Requires one finite, non-negative [value].
  static void _requireNonNegative(double value, String label) {
    if (!value.isFinite || value < 0) {
      throw AbrWriteException(message: '$label must be finite and non-negative');
    }
  }

  /// Adds Photoshop's conventional terminal null without duplicating it.
  static String _terminatedPhotoshopString(String value) => value.endsWith('\u0000') ? value : '$value\u0000';
}
