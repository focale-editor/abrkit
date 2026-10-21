import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';
import 'package:test/test.dart';

/// Covers semantic edits against an independent Photoshop preset and new tips.
void main() {
  test('Edits invalidate preserved sections in strict and permissive output', () {
    final AbrFile file = AbrDecoder.decode(base64Decode(File('test/fixtures/photoshop_dynamics.abr.b64').readAsStringSync().replaceAll(RegExp(r'\s'), '')));
    final AbrBrush source = file.brushes.single;
    final AbrBrushSettings settings = source.settings!;
    final AbrBrush edited = source.edited(
      name: 'Changed brush',
      settings: AbrBrushSettings(
        spacing: 0.37,
        noise: true,
        wetEdges: true,
        buildUp: settings.buildUp,
        useBrushSize: settings.useBrushSize,
        rawDescriptor: settings.rawDescriptor,
        scatter: settings.scatter,
        transfer: settings.transfer,
        shapeDynamics: settings.shapeDynamics,
        texture: settings.texture,
        dualBrush: settings.dualBrush,
        colorDynamics: settings.colorDynamics,
        pose: settings.pose,
        toolOptions: settings.toolOptions,
        protectTexture: settings.protectTexture,
        interpretation: settings.interpretation,
      ),
    );
    final AbrFile changed = file.withBrush(0, edited);
    for (final AbrEncodeMode mode in AbrEncodeMode.values) {
      final AbrFile decoded = AbrDecoder.decode(AbrEncoder.encode(changed, options: AbrEncodeOptions(mode: mode)));
      expect(decoded.brushes.single.name, 'Changed brush');
      expect(decoded.brushes.single.settings!.spacing, closeTo(0.37, 1e-12));
      expect(decoded.brushes.single.settings!.noise, isTrue);
      expect(decoded.brushes.single.settings!.wetEdges, isTrue);
      expect(decoded.brushes.single.settings!.shapeDynamics!.size.jitter, settings.shapeDynamics!.size.jitter);
      expect(decoded.samples.single.alpha, file.samples.single.alpha);
      expect(decoded.brushes.single.rawDescriptor!.value('Brsh'), isA<PsObjectValue>());
    }
    expect(source.name, isNot('Changed brush'));
  });

  test('Retains unknown preset and tip fields during typed shape edits', () {
    final AbrBrush source = AbrDecoder.decode(
      AbrEncoder.encode(
        AbrFile.modern(
          brushes: [
            AbrBrush(
              name: 'Base',
              shape: const AbrComputedBrushShape(rawDescriptor: null, diameter: 20, hardness: 0.8, angle: 10, roundness: 1, spacing: 0.2, spacingEnabled: true, flipX: false, flipY: false),
            ),
          ],
        ),
      ),
    ).brushes.single;
    final PsDescriptor tip = source.shape.rawDescriptor!.withValue('FutureTip', const PsStringValue(value: 'opaque'));
    final AbrBrush marked = AbrBrush(
      name: source.name,
      shape: source.shape,
      rawDescriptor: source.rawDescriptor!.withValue('FuturePreset', const PsIntegerValue(value: 42)).withValue('Brsh', PsObjectValue(value: tip)),
    );
    final AbrBrush changed = marked.edited(
      shape: const AbrComputedBrushShape(diameter: 50, hardness: 0.5, angle: 15, roundness: 0.75, spacing: 0.3, spacingEnabled: true, flipX: true, flipY: false, rawDescriptor: null),
    );
    expect(changed.rawDescriptor!.integerValue('FuturePreset'), 42);
    expect(changed.shape.rawDescriptor!.stringValue('FutureTip'), 'opaque');
    expect((changed.shape as AbrComputedBrushShape).diameter, 50);
    expect(changed.shape.rawDescriptor!.value('Dmtr'), isA<PsUnitFloatValue>());
  });

  test('Synthesizes bristle and erodible presets without source descriptors', () {
    const AbrBristleBrushShape bristle = AbrBristleBrushShape(
      shape: AbrBristleShape.roundPoint,
      shapeCode: 0,
      diameter: 32,
      angle: 12,
      density: 0.4,
      length: 0.5,
      clumping: 0.1,
      thickness: 0.2,
      stiffness: 0.8,
      physics: true,
      spacing: 0.1,
      spacingEnabled: true,
      flipX: false,
      flipY: true,
    );
    final AbrErodibleBrushShape erodible = AbrErodibleBrushShape(
      tipType: AbrErodibleTipType.custom,
      tipTypeCode: 5,
      shape: AbrBristleShape.roundPoint,
      shapeCode: 0,
      diameter: 24,
      angle: 0,
      lengthRatio: 0.8,
      hardness: 0.7,
      physics: true,
      spacing: 0.2,
      spacingEnabled: true,
      flipX: false,
      flipY: false,
      airbrushCutoffAngle: 15,
      airbrushGranularity: 0.3,
      airbrushStreakiness: 0.4,
      airbrushSplatSize: 0.2,
      airbrushSplatCount: 6,
      gridSize: 2,
      heightMap: Uint8List.fromList([1, 2, 3, 4]),
    );
    final AbrFile decoded = AbrDecoder.decode(
      AbrEncoder.encode(
        AbrFile.modern(
          brushes: [
            AbrBrush(name: 'Bristle', shape: bristle),
            AbrBrush(name: 'Erodible', shape: erodible),
          ],
        ),
      ),
    );
    final AbrBristleBrushShape first = decoded.brushes[0].shape as AbrBristleBrushShape;
    final AbrErodibleBrushShape second = decoded.brushes[1].shape as AbrErodibleBrushShape;
    expect(first.rawDescriptor!.numberValue('Dmtr')!.unit, '#Pxl');
    expect(first.rawDescriptor!.numberValue('Angl')!.unit, '#Ang');
    expect(first.diameter, 32);
    expect(first.density, 0.4);
    expect(first.flipY, isTrue);
    expect(second.heightMap, [1, 2, 3, 4]);
    expect(second.airbrushSplatCount, 6);
    expect(second.hardness, 0.7);
  });
}
