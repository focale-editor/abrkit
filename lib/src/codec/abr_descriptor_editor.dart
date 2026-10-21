import 'dart:typed_data';

import 'package:abrkit/src/codec/abr_descriptor_mapper.dart';
import 'package:abrkit/src/model/abr_brush.dart';
import 'package:abrkit/src/model/abr_file.dart';
import 'package:abrkit/src/model/abr_options.dart';
import 'package:pscore/pscore.dart';

/// Applies typed changes while retaining unrecognized preset and shape fields.
extension AbrBrushEditing on AbrBrush {
  /// Replaces the requested fields and updates the authoritative descriptor.
  AbrBrush edited({String? name, AbrBrushShape? shape, AbrBrushSettings? settings}) {
    PsDescriptor descriptor = rawDescriptor ?? const PsDescriptor(name: '', classId: 'brushPreset');
    if (name != null || rawDescriptor == null) {
      descriptor = descriptor.withValue('Nm  ', PsStringValue(value: '${name ?? this.name}\u0000'));
    }
    if (shape != null || rawDescriptor == null) {
      descriptor = descriptor.withValue('Brsh', PsObjectValue(value: AbrDescriptorEditor.shape(shape ?? this.shape, source: descriptor.objectValue('Brsh'))));
    }
    if (settings != null) {
      descriptor = AbrDescriptorEditor.settings(settings, source: descriptor);
    } else if (rawDescriptor == null && this.settings != null) {
      descriptor = AbrDescriptorEditor.settings(this.settings!, source: descriptor);
    }
    return AbrDescriptorMapper.brush(descriptor);
  }
}

/// Writes all typed brush engines and behavioral groups over retained descriptors.
abstract final class AbrDescriptorEditor {
  /// Rebuilds known geometry without discarding shape extension fields.
  static PsDescriptor shape(AbrBrushShape value, {PsDescriptor? source}) {
    if (value is AbrUnknownBrushShape) {
      return value.rawDescriptor ?? (throw const AbrWriteException(message: 'An unknown tip requires its descriptor'));
    }
    final double diameter = switch (value) {
      AbrComputedBrushShape(:final diameter) || AbrSampledBrushShape(:final diameter) || AbrBristleBrushShape(:final diameter) || AbrErodibleBrushShape(:final diameter) => diameter,
      AbrUnknownBrushShape() => 0,
    };
    if (!diameter.isFinite || diameter <= 0) {
      throw const AbrWriteException(message: 'Brush diameter must be finite and positive');
    }
    final String classId = switch (value) {
      AbrComputedBrushShape() => 'computedBrush',
      AbrSampledBrushShape() => 'sampledBrush',
      AbrBristleBrushShape() => 'dBrush',
      AbrErodibleBrushShape() => 'dTips',
      AbrUnknownBrushShape() => throw StateError('Unreachable tip'),
    };
    final PsDescriptor base = value.rawDescriptor ?? (source?.classId == classId ? source! : PsDescriptor(name: '', classId: classId));
    return switch (value) {
      final AbrComputedBrushShape value => _update(base, {
        'Dmtr': _unit(value.diameter, '#Pxl'),
        'Hrdn': _percent(value.hardness),
        'Angl': _unit(value.angle, '#Ang'),
        'Rndn': _percent(value.roundness),
        'Spcn': _percent(value.spacing),
        'Intr': _boolean(value.spacingEnabled),
        'flipX': _boolean(value.flipX),
        'flipY': _boolean(value.flipY),
      }),
      final AbrSampledBrushShape value => _update(base, {
        'sampledData': _string(value.sampleId),
        if (value.name != null) 'Nm  ': _string(value.name!),
        'Dmtr': _unit(value.diameter, '#Pxl'),
        'Angl': _unit(value.angle, '#Ang'),
        'Rndn': _percent(value.roundness),
        'Spcn': _percent(value.spacing),
        'Intr': _boolean(value.spacingEnabled),
        'flipX': _boolean(value.flipX),
        'flipY': _boolean(value.flipY),
      }),
      final AbrBristleBrushShape value => _update(base, {
        'Dmtr': _unit(value.diameter, '#Pxl'),
        'Angl': _unit(value.angle, '#Ang'),
        'Dnst': _percent(value.density),
        'Lngt': _percent(value.length),
        'clumping': _percent(value.clumping),
        'thickness': _percent(value.thickness),
        'stiffness': _percent(value.stiffness),
        'physics': _boolean(value.physics),
        'Spcn': _percent(value.spacing),
        'Intr': _boolean(value.spacingEnabled),
        'flipX': _boolean(value.flipX),
        'flipY': _boolean(value.flipY),
        'Shp ': _integer(value.shapeCode),
      }),
      final AbrErodibleBrushShape value => _update(base, {
        'Dmtr': _unit(value.diameter, '#Pxl'),
        'Angl': _unit(value.angle, '#Ang'),
        'dtipsLengthRatio': _percent(value.lengthRatio),
        'dtipsHardness': _percent(value.hardness),
        if (value.gridSize != null) 'dtipsGridSize': _integer(value.gridSize!),
        'physics': _boolean(value.physics),
        'Spcn': _percent(value.spacing),
        'Intr': _boolean(value.spacingEnabled),
        'flipX': _boolean(value.flipX),
        'flipY': _boolean(value.flipY),
        'dtipsAirbrushCutoffAngle': _number(value.airbrushCutoffAngle),
        'dtipsAirbrushGranularity': _percent(value.airbrushGranularity),
        'dtipsAirbrushStreakiness': _percent(value.airbrushStreakiness),
        'dtipsAirbrushSplatSize': _percent(value.airbrushSplatSize),
        'dtipsAirbrushSplatCount': _integer(value.airbrushSplatCount),
        'Shp ': _integer(value.shapeCode),
        'dtipsType': _integer(value.tipTypeCode),
        'dtipsErodibleTipHeightMap': PsRawValue(value: value.heightMap),
      }),
      AbrUnknownBrushShape() => base,
    };
  }

  /// Rebuilds behavior while retaining unknown root and nested properties.
  static PsDescriptor settings(AbrBrushSettings value, {PsDescriptor? source}) {
    PsDescriptor result = _update(source ?? value.rawDescriptor, {
      'Spcn': _percent(value.spacing),
      'Nose': _boolean(value.noise),
      'Wtdg': _boolean(value.wetEdges),
      'Rpt ': _boolean(value.buildUp),
      'useBrushSize': _boolean(value.useBrushSize),
      if (value.protectTexture != null) 'protectTexture': _boolean(value.protectTexture!),
      if (value.interpretation != null) 'interpretation': _boolean(value.interpretation!),
      'useTipDynamics': _boolean(value.shapeDynamics != null),
      'useScatter': _boolean(value.scatter != null),
      'useTexture': _boolean(value.texture != null),
      'useColorDynamics': _boolean(value.colorDynamics != null),
      'usePaintDynamics': _boolean(value.transfer != null),
      'useBrushPose': _boolean(value.pose != null),
    });

    if (value.shapeDynamics != null) {
      result = _shapeDynamics(value.shapeDynamics!, result);
    }
    if (value.scatter != null) {
      result = _scatter(value.scatter!, result);
    }
    if (value.texture != null) {
      result = _texture(value.texture!, result);
    }
    if (value.colorDynamics != null) {
      result = _colorDynamics(value.colorDynamics!, result);
    }
    if (value.transfer != null) {
      result = _transfer(value.transfer!, result);
    }
    if (value.pose != null) {
      result = _pose(value.pose!, result);
    }
    if (value.dualBrush case final AbrDualBrushSettings dual) {
      result = result.withValue(
        'dualBrush',
        PsObjectValue(
          value: _dual(dual, result.objectValue('dualBrush') ?? const PsDescriptor(name: '', classId: 'dualBrush')),
        ),
      );
    } else if (result.objectValue('dualBrush') case final PsDescriptor dual) {
      result = result.withValue('dualBrush', PsObjectValue(value: dual.withValue('useDualBrush', _boolean(false))));
    }
    if (value.toolOptions case final AbrToolOptions tool) {
      result = result.withValue('toolOptions', PsObjectValue(value: _tool(tool, tool.rawDescriptor)));
    } else {
      result = result.withoutValue('toolOptions');
    }
    return result;
  }

  /// Serializes the typed AbrShapeDynamicsSettings properties over their source fields.
  static PsDescriptor _shapeDynamics(AbrShapeDynamicsSettings value, PsDescriptor base) => _update(base, {
    'minimumDiameter': _percent(value.minimumDiameter),
    'minimumRoundness': _percent(value.minimumRoundness),
    'tiltScale': _percent(value.tiltScale),
    'flipX': _boolean(value.flipX),
    'flipY': _boolean(value.flipY),
    'brushProjection': _boolean(value.projectToStroke),
    'szVr': PsObjectValue(value: _dynamics(value.size)),
    'angleDynamics': PsObjectValue(value: _dynamics(value.angle)),
    'roundnessDynamics': PsObjectValue(value: _dynamics(value.roundness)),
  });

  /// Serializes the typed AbrScatterSettings properties over their source fields.
  static PsDescriptor _scatter(AbrScatterSettings value, PsDescriptor base) => _update(base, {
    'bothAxes': _boolean(value.bothAxes),
    'Cnt ': _integer(value.count),
    'scatterDynamics': PsObjectValue(value: _dynamics(value.scatter)),
    'countDynamics': PsObjectValue(value: _dynamics(value.countDynamics)),
  });

  /// Serializes the typed AbrTextureSettings properties over their source fields.
  static PsDescriptor _texture(AbrTextureSettings value, PsDescriptor base) => _update(base, {
    'InvT': _boolean(value.invert),
    'textureScale': _percent(value.scale),
    'textureBrightness': _integer(value.brightness),
    'textureContrast': _integer(value.contrast),
    'textureBlendMode': _enumeration(value.blendMode),
    'textureDepth': _percent(value.depth),
    'minimumDepth': _percent(value.minimumDepth),
    'TxtC': _boolean(value.eachTip),
    'textureDepthDynamics': PsObjectValue(value: _dynamics(value.depthDynamics)),
    'Txtr': PsObjectValue(
      value: _update(base.objectValue('Txtr') ?? const PsDescriptor(name: '', classId: 'Ptrn'), {'Idnt': _string(value.patternId), 'Nm  ': _string(value.patternName)}),
    ),
  });

  /// Serializes the typed AbrDualBrushSettings properties over their source fields.
  static PsDescriptor _dual(AbrDualBrushSettings value, PsDescriptor base) => _update(base, {
    'Flip': _boolean(value.flip),
    'BlnM': _enumeration(value.blendMode),
    'useScatter': _boolean(value.scatterEnabled),
    'Spcn': _percent(value.spacing),
    'Cnt ': _integer(value.count),
    'bothAxes': _boolean(value.bothAxes),
    'countDynamics': PsObjectValue(value: _dynamics(value.countDynamics)),
    'scatterDynamics': PsObjectValue(value: _dynamics(value.scatterDynamics)),
    'useDualBrush': _boolean(true),
    'Brsh': PsObjectValue(value: shape(value.shape, source: base.objectValue('Brsh'))),
  });

  /// Serializes the typed AbrColorDynamicsSettings properties over their source fields.
  static PsDescriptor _colorDynamics(AbrColorDynamicsSettings value, PsDescriptor base) => _update(base, {
    'H   ': _percent(value.hue),
    'Strt': _percent(value.saturation),
    'Brgh': _percent(value.brightness),
    'purity': _percent(value.purity),
    'colorDynamicsPerTip': _boolean(value.perTip),
    'clVr': PsObjectValue(value: _dynamics(value.foregroundBackground)),
  });

  /// Serializes the typed AbrTransferSettings properties over their source fields.
  static PsDescriptor _transfer(AbrTransferSettings value, PsDescriptor base) => _update(base, {
    'prVr': PsObjectValue(value: _dynamics(value.flow)),
    'opVr': PsObjectValue(value: _dynamics(value.opacity)),
    'wtVr': PsObjectValue(value: _dynamics(value.wetness)),
    'mxVr': PsObjectValue(value: _dynamics(value.mix)),
  });

  /// Serializes the typed AbrBrushPoseSettings properties over their source fields.
  static PsDescriptor _pose(AbrBrushPoseSettings value, PsDescriptor base) => _update(base, {
    'overridePoseAngle': _boolean(value.overrideAngle),
    'overridePoseTiltX': _boolean(value.overrideTiltX),
    'overridePoseTiltY': _boolean(value.overrideTiltY),
    'overridePosePressure': _boolean(value.overridePressure),
    'brushPosePressure': _percent(value.pressure),
    'brushPoseTiltX': _number(value.tiltX),
    'brushPoseTiltY': _number(value.tiltY),
    'brushPoseAngle': _number(value.angle),
  });

  /// Serializes the typed AbrToolOptions properties over their source fields.
  static PsDescriptor _tool(AbrToolOptions value, PsDescriptor base) {
    PsDescriptor retained = base;
    final Map<String, Object?> optional = {
      'wetness': value.wetness,
      'dryness': value.dryness,
      'mix': value.mix,
      'autoFill': value.autoFill,
      'autoClean': value.autoClean,
      'loadSolidColorOnly': value.loadSolidColorOnly,
      'sampleAllLayers': value.sampleAllLayers,
      'SmdF': value.smudgeFingerPainting,
      'SmdS': value.smudgeSampleAllLayers,
      'Prs ': value.strength,
      'prVr': value.flowDynamics,
      'opVr': value.opacityDynamics,
      'szVr': value.sizeDynamics,
    };
    for (final MapEntry<String, Object?> entry in optional.entries) {
      if (entry.value == null) {
        retained = retained.withoutValue(entry.key);
      }
    }
    return _update(retained, {
      'brushPreset': _boolean(value.brushPreset),
      'flow': _number(value.flow),
      'Opct': _number(value.opacity),
      'Smoo': _number(value.smooth),
      'Md  ': _enumeration(value.blendMode),
      'smoothing': _boolean(value.smoothing),
      'smoothingValue': _number(value.smoothingValue),
      'smoothingRadiusMode': _boolean(value.smoothingRadiusMode),
      'smoothingCatchup': _boolean(value.smoothingCatchUp),
      'smoothingCatchupAtEnd': _boolean(value.smoothingCatchUpAtEnd),
      'smoothingZoomCompensation': _boolean(value.smoothingZoomCompensation),
      'pressureSmoothing': _boolean(value.pressureSmoothing),
      'usePressureOverridesSize': _boolean(value.pressureOverridesSize),
      'usePressureOverridesOpacity': _boolean(value.pressureOverridesOpacity),
      'useLegacy': _boolean(value.legacy),
      if (value.wetness != null) 'wetness': _number(value.wetness!),
      if (value.dryness != null) 'dryness': _number(value.dryness!),
      if (value.mix != null) 'mix': _number(value.mix!),
      if (value.autoFill != null) 'autoFill': _boolean(value.autoFill!),
      if (value.autoClean != null) 'autoClean': _boolean(value.autoClean!),
      if (value.loadSolidColorOnly != null) 'loadSolidColorOnly': _boolean(value.loadSolidColorOnly!),
      if (value.sampleAllLayers != null) 'sampleAllLayers': _boolean(value.sampleAllLayers!),
      if (value.smudgeFingerPainting != null) 'SmdF': _boolean(value.smudgeFingerPainting!),
      if (value.smudgeSampleAllLayers != null) 'SmdS': _boolean(value.smudgeSampleAllLayers!),
      if (value.strength != null) 'Prs ': _number(value.strength!),
      if (value.flowDynamics != null) 'prVr': PsObjectValue(value: _dynamics(value.flowDynamics!)),
      if (value.opacityDynamics != null) 'opVr': PsObjectValue(value: _dynamics(value.opacityDynamics!)),
      if (value.sizeDynamics != null) 'szVr': PsObjectValue(value: _dynamics(value.sizeDynamics!)),
    });
  }

  /// Writes a modulation descriptor without normalizing unknown controller codes.
  static PsDescriptor _dynamics(AbrDynamics value) => _update(value.rawDescriptor.classId == 'nullDynamics' ? const PsDescriptor(name: '', classId: 'brVr') : value.rawDescriptor, {
    'bVTy': _integer(value.controlCode),
    'fStp': _integer(value.fadeSteps),
    'jitter': _percent(value.jitter),
    'Mnm ': _percent(value.minimum),
  });

  /// Merges typed values in place while preserving unknown descriptor entries.
  static PsDescriptor _update(PsDescriptor source, Map<String, PsDescriptorValue> values) {
    PsDescriptor result = source;
    for (final MapEntry<String, PsDescriptorValue> entry in values.entries) {
      final PsDescriptorValue? previous = source.value(entry.key);
      final PsDescriptorValue replacement = switch ((previous, entry.value)) {
        (PsUnitFloatValue(:final String unit), PsDoubleValue(:final double value)) => PsUnitFloatValue(unit: unit, value: value),
        (PsEnumeratedValue(:final String typeId), PsEnumeratedValue(:final String value)) => PsEnumeratedValue(typeId: typeId, value: value),
        _ => entry.value,
      };
      result = result.withValue(entry.key, replacement);
    }
    return result;
  }

  /// Checks a numeric field before encoding a finite Adobe double.
  static PsDoubleValue _number(double value) {
    if (!value.isFinite) {
      throw const AbrWriteException(message: 'Brush values must be finite');
    }
    return PsDoubleValue(value: value);
  }

  /// Attaches Photoshop's canonical unit to newly synthesized geometry.
  static PsUnitFloatValue _unit(double value, String unit) => PsUnitFloatValue(unit: unit, value: _number(value).value);

  /// Converts a normalized setting to Photoshop's percent scale.
  static PsUnitFloatValue _percent(double value) => PsUnitFloatValue(unit: '#Prc', value: _number(value * 100).value);

  /// Wraps a signed descriptor integer after checking its range.
  static PsIntegerValue _integer(int value) {
    if (value < -0x80000000 || value > 0x7fffffff) {
      throw const AbrWriteException(message: 'Brush integer is outside the signed 32-bit range');
    }
    return PsIntegerValue(value: value);
  }

  /// Wraps one Boolean setting.
  static PsBooleanValue _boolean(bool value) => PsBooleanValue(value: value);

  /// Wraps one descriptor text value.
  static PsStringValue _string(String value) => PsStringValue(value: value);

  /// Retains the Photoshop blend-mode identifier.
  static PsEnumeratedValue _enumeration(String value) => PsEnumeratedValue(typeId: 'BlnM', value: value);
}

/// Updates the descriptor roots authoritative for modern brush export.
extension AbrFileEditing on AbrFile {
  /// Replaces one preset without changing the positional library hierarchy.
  AbrFile withBrush(int index, AbrBrush brush) {
    RangeError.checkValidIndex(index, brushes);
    final List<AbrBrush> updated = [...brushes]..[index] = brush;
    final List<PsDescriptor> roots = [];
    int remaining = index;
    bool replaced = false;
    for (final PsDescriptor root in descriptors) {
      final List<PsDescriptorValue>? entries = root.listValue('Brsh');
      if (!replaced && entries != null && remaining < entries.length) {
        final List<PsDescriptorValue> values = [...entries]..[remaining] = PsObjectValue(value: brush.edited().rawDescriptor!);
        roots.add(root.withValue('Brsh', PsListValue(values: values)));
        replaced = true;
      } else {
        roots.add(root);
        remaining -= entries?.length ?? 0;
      }
    }
    if (descriptors.isNotEmpty && !replaced) {
      throw const AbrWriteException(message: 'Brush index does not match the retained descriptor roots');
    }
    return AbrFile(
      version: version,
      subversion: subversion,
      family: family,
      brushes: updated,
      samples: samples,
      patterns: patterns,
      hierarchy: hierarchy,
      descriptors: roots,
      hierarchyDescriptors: hierarchyDescriptors,
      sections: [
        for (final AbrTaggedSection section in sections)
          if (section.key == 'desc') PsTaggedBlock(signature: section.signature, key: section.key, declaredLength: section.declaredLength, data: Uint8List(0)) else section,
      ],
      trailingData: trailingData,
      trailingByteCount: trailingByteCount,
      warnings: warnings,
    );
  }
}
