<p align="center">
  <img src="screenshots/overview.png" alt="AbrKit package illustration" width="180">
</p>

# AbrKit

AbrKit is a pure Dart codec for Adobe Photoshop brush libraries (`.abr`). It decodes and encodes both the documented legacy records and the descriptor-based modern format without Flutter, native code, or a third-party ABR parser.

The package is designed for editors that need more than thumbnails: it exposes sampled and procedural tips, brush settings, embedded texture patterns, group hierarchy, unknown extension data, and the complete Photoshop Action Descriptors.

## Supported data

- Legacy ABR versions 1 and 2, including computed and sampled brushes.
- Modern ABR versions 6, 7, 9, and 10 with subversions 1 and 2.
- `samp` tips at 1, 8, and 16 bits, stored raw or with row-based PackBits compression.
- `desc` brush presets and their complete version 16 Action Descriptors.
- `patt` embedded patterns in every Photoshop color mode, with 1, 8, 16, and 32-bit raw or PackBits channels.
- `phry` brush-group hierarchy entries.
- Computed, sampled, bristle, erodible, custom height-map, and airbrush tips.
- Shape dynamics, scattering, texture, dual brush, color dynamics, transfer, brush pose, and saved tool options.
- Unknown sections, descriptor properties, compression codes, and legacy records preserved for forward compatibility.
- Legacy and modern ABR writing, including sampled tips, Action Descriptors, embedded patterns, hierarchy data, and preserved unknown sections.

Modern ABR is not publicly specified in full. AbrKit therefore keeps the generic descriptor and original bounded payloads alongside typed values so applications do not lose fields that have not yet been given a semantic model.

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:abrkit/abrkit.dart';

final Uint8List bytes = await File('brushes.abr').readAsBytes();
final AbrFile library = AbrDecoder.decode(bytes);

for (final AbrBrush brush in library.brushes) {
  print(brush.name);

  switch (brush.shape) {
    case AbrSampledBrushShape shape:
      final AbrSample? sample = library.sampleFor(shape);
      if (sample != null) {
        print('${sample.width} × ${sample.height}');
      }
    case AbrComputedBrushShape shape:
      print('${shape.diameter}px at ${shape.hardness * 100}% hardness');
    case AbrBrushShape():
      print(brush.shape.runtimeType);
  }
}

final Uint8List output = AbrEncoder.encode(library);
await File('brushes-copy.abr').writeAsBytes(output, flush: true);
```

`AbrSample.alpha` contains one normalized 8-bit mask value per pixel in row-major order. For 16-bit sources, `AbrSample.alpha16` also retains every full-precision sample. Bounds retain the original Photoshop-space origin.

### Creating square and diamond tips

Standard computed ABR tips are elliptical. For modern files, create one canonical sampled square and express a diamond as a 45-degree descriptor transform instead of rasterizing a second bitmap:

```dart
final AbrSample squareSample = AbrSample.square(
  id: 'canonical-square',
  sampleSize: 256,
  hardness: 0.85,
  depth: 16,
);
final AbrFile geometricLibrary = AbrFile.modern(
  brushes: [
    AbrBrush.sampled(
      name: 'Square',
      sampleId: squareSample.id,
      diameter: 64,
    ),
    AbrBrush.sampled(
      name: 'Diamond',
      sampleId: squareSample.id,
      diameter: 64,
      angle: 45,
    ),
  ],
  samples: [squareSample],
);
final Uint8List geometricBytes = AbrEncoder.encode(geometricLibrary);
```

`AbrSample.square` analytically generates a symmetric mask with configurable hardness, precision, compression, and supersampling. Reusing its identifier deduplicates the bitmap while each modern `sampledBrush` keeps its own diameter, angle, roundness, spacing, and flips. Legacy versions 1 and 2 do not store those transforms for sampled tips, so their transforms must still be baked into separate bitmaps.

## Reusable `dart:convert` API

`AbrCodec` implements `Codec<AbrFile, List<int>>` and keeps decoding and encoding policies together in one immutable value:

```dart
const AbrCodec codec = AbrCodec(
  decodeOptions: AbrDecodeOptions(mode: AbrDecodeMode.strict),
  encodeOptions: AbrEncodeOptions(mode: AbrEncodeMode.strict),
);

final AbrFile library = codec.decode(bytes);
final Uint8List output = codec.encode(library);
```

The `List<int>` binary type allows composition with standard codecs such as `base64`; direct `encode` calls still return `Uint8List`. `AbrEncoder` and `AbrDecoder` are also configurable `Converter` implementations. Every conversion consumes or produces one complete in-memory ABR file rather than an incremental byte stream.

## Decoding and encoding policies

Tolerant decoding is the default. Recoverable extensions are preserved and reported through `AbrFile.warnings`:

```dart
final AbrFile library = AbrDecoder.decode(bytes);
for (final AbrWarning warning in library.warnings) {
  print(warning);
}
```

Strict mode turns every compatibility warning into an `AbrFormatException`:

```dart
final AbrFile library = AbrDecoder.decode(
  bytes,
  options: const AbrDecodeOptions(mode: AbrDecodeMode.strict),
);
```

`AbrDecodeOptions` also bounds file size, section size, decoded bitmap memory, dimensions, collection counts, and Action Descriptor complexity for untrusted input. Set `preserveSectionData` to `false` when the typed models and descriptors are sufficient and retaining complete section payloads would use too much memory.

`AbrEncoder.encode` writes the same legacy or modern family represented by `AbrFile`. Legacy computed and sampled records are rebuilt from their typed shapes and sample pixels. Modern `samp`, `desc`, `patt`, and `phry` sections are regenerated from samples, complete Action Descriptors, embedded pattern models, and hierarchy descriptors. This remains possible with `preserveSectionData: false`; only unknown or malformed sections need their original payload.

Modern typed brush settings are views over `AbrBrush.rawDescriptor` and `AbrFile.descriptors`. Preserved complete descriptors are authoritative when writing a `desc` section, so descriptor-level edits should be applied there before encoding. For newly created computed or sampled brushes without source descriptors, the encoder synthesizes canonical descriptors from their typed shapes.

Permissive output retains compatible source padding, extension values, and trailing bytes where available. Complete preserved modern section payloads take precedence in this mode, making it suitable for lossless reconstruction; use the default strict mode when edits to typed samples, descriptors, patterns, or hierarchy must be regenerated:

```dart
final Uint8List output = AbrEncoder.encode(
  library,
  options: const AbrEncodeOptions(mode: AbrEncodeMode.permissive),
);
```

Use `includeUnknownSections: false` when section payload preservation was disabled. Unrepresentable values and missing required payloads produce an `AbrWriteException`.

## Scope

AbrKit reads and writes libraries but does not render complete Photoshop brush strokes. A host editor remains responsible for the dab engine, dynamics over time, texture compositing, and tool behavior. The raw descriptors allow those behaviors to evolve without reparsing or discarding Photoshop-specific settings.

See [docs/ABR.md](docs/ABR.md) for the implemented binary-layout notes and compatibility matrix.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [GIMP ABR reader](https://github.com/GNOME/gimp/blob/master/app/core/gimpbrush-load.c)
- [ag-psd ABR reader](https://github.com/Agamnentzar/ag-psd/blob/master/src/abr.ts)
- [Patchy ABR reader](https://github.com/SethRobinson/Patchy/blob/main/src/psd/abr_reader.cpp)

AbrKit is an independent implementation and is not affiliated with or endorsed by Adobe.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
