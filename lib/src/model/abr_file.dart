import 'dart:typed_data';

import 'package:abrkit/src/model/abr_brush.dart';
import 'package:abrkit/src/model/abr_options.dart';
import 'package:abrkit/src/model/abr_pattern.dart';
import 'package:abrkit/src/model/abr_sample.dart';
import 'package:pscore/pscore.dart';

/// Structural family used by an ABR library.
enum AbrFormatFamily {
  /// Photoshop 3-era fixed-layout versions 1 and 2.
  legacy,

  /// Tagged `8BIM` versions 6, 7, 9, and 10.
  modern,
}

/// One modern `8BIM` section, including unknown forward-compatible payloads.
final class AbrTaggedSection {
  /// Four-byte signature, normally `8BIM`.
  final String signature;

  /// Four-byte section key such as `samp`, `desc`, `patt`, or `phry`.
  final String key;

  /// Absolute offset of the section signature.
  final int offset;

  /// Unpadded section payload.
  final Uint8List data;

  /// Creates an immutable tagged section.
  AbrTaggedSection({
    required this.signature,
    required this.key,
    required this.offset,
    required Uint8List data,
  }) : data = Uint8List.fromList(data).asUnmodifiableView();
}

/// One brush-group slot from a modern `phry` hierarchy descriptor.
final class AbrHierarchyEntry {
  /// Position of the slot in the source hierarchy list.
  final int index;

  /// Group or preset name, when this slot represents an object.
  final String? name;

  /// Photoshop UUID associated with [name], when present.
  final String? id;

  /// Complete hierarchy object, or `null` for an empty slot.
  final PsDescriptor? rawDescriptor;

  /// Creates a decoded hierarchy slot.
  const AbrHierarchyEntry({
    required this.index,
    this.name,
    this.id,
    this.rawDescriptor,
  });
}

/// Complete decoded contents of one Adobe Photoshop brush library.
final class AbrFile {
  /// Major ABR version exactly as stored in the file.
  final int version;

  /// Modern ABR subversion, or `null` for legacy files.
  final int? subversion;

  /// Structural family selected from [version].
  final AbrFormatFamily family;

  /// Named brush presets in source order.
  final List<AbrBrush> brushes;

  /// Decoded grayscale brush-tip samples in source order.
  final List<AbrSample> samples;

  /// Patterns embedded for brush textures.
  final List<AbrPattern> patterns;

  /// Decoded brush-group hierarchy slots.
  final List<AbrHierarchyEntry> hierarchy;

  /// Complete root descriptors from every `desc` section.
  final List<PsDescriptor> descriptors;

  /// Complete root descriptors from every `phry` section.
  final List<PsDescriptor> hierarchyDescriptors;

  /// Every modern tagged section, including unknown keys.
  final List<AbrTaggedSection> sections;

  /// Recoverable compatibility issues encountered while decoding.
  final List<AbrWarning> warnings;

  /// Last sample for each identifier, matching Photoshop's reference behavior.
  final Map<String, AbrSample> _samplesById;

  /// Creates an immutable decoded ABR library.
  AbrFile({
    required this.version,
    required this.subversion,
    required this.family,
    required List<AbrBrush> brushes,
    required List<AbrSample> samples,
    required List<AbrPattern> patterns,
    required List<AbrHierarchyEntry> hierarchy,
    required List<PsDescriptor> descriptors,
    required List<PsDescriptor> hierarchyDescriptors,
    required List<AbrTaggedSection> sections,
    required List<AbrWarning> warnings,
  }) : brushes = List<AbrBrush>.unmodifiable(brushes),
       samples = List<AbrSample>.unmodifiable(samples),
       patterns = List<AbrPattern>.unmodifiable(patterns),
       hierarchy = List<AbrHierarchyEntry>.unmodifiable(hierarchy),
       descriptors = List<PsDescriptor>.unmodifiable(descriptors),
       hierarchyDescriptors = List<PsDescriptor>.unmodifiable(hierarchyDescriptors),
       sections = List<AbrTaggedSection>.unmodifiable(sections),
       warnings = List<AbrWarning>.unmodifiable(warnings),
       _samplesById = Map<String, AbrSample>.unmodifiable(<String, AbrSample>{for (final AbrSample sample in samples) sample.id: sample});

  /// Returns the last sample matching [id], or `null` when it is external or missing.
  AbrSample? sampleById(String id) => _samplesById[id];

  /// Resolves the bitmap referenced by a sampled [shape].
  AbrSample? sampleFor(AbrSampledBrushShape shape) => sampleById(shape.sampleId);
}
