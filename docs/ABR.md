# ABR implementation notes

This document records the format variants implemented by AbrKit. It is an interoperability guide, not a claim that the modern proprietary format is fully specified by Adobe.

## Compatibility matrix

| Family | Versions | Header | Presets | Bitmap tips | Patterns | Hierarchy |
| --- | --- | --- | --- | --- | --- | --- |
| Legacy | 1, 2 | major version and brush count | Fixed computed or sampled records | 1/8/16-bit raw or PackBits | Not defined | Not defined |
| Modern | 6, 7, 9, 10 | major version and subversion 1 or 2 | Version 16 Action Descriptor in `desc` | `samp` section | `patt` section | `phry` section |

All structural integers and floating-point values are read in big-endian order. Length-bounded payloads are used throughout so an unknown record can be retained without guessing its internal layout.

## Legacy versions 1 and 2

The file starts with:

```text
uint16 majorVersion
uint16 brushCount
```

Each record is:

```text
uint16 brushType
uint32 payloadLength
byte[payloadLength] payload
```

Known brush types are `1` for a computed brush and `2` for a sampled brush. Unknown types are represented by `AbrUnknownBrushShape` and their complete payload remains available.

A computed payload contains miscellaneous data, spacing, diameter, roundness, angle, and hardness. A sampled payload contains miscellaneous data, spacing, an optional version 2 Unicode name, anti-aliasing, short and long bounds, depth, compression, and the grayscale tip data.

## Modern versions

The modern header is:

```text
uint16 majorVersion
uint16 subversion
```

It is followed by tagged sections:

```text
char[4] signature    // normally "8BIM"
char[4] key
uint32 payloadLength
byte[payloadLength] payload
byte[0..3] alignment
```

Sections are normally aligned to four bytes. Real exporters sometimes omit the alignment after the final section, which AbrKit accepts. Unknown signatures and keys are retained and become warnings in tolerant mode.

### `samp`

The section is a sequence of length-prefixed entries aligned to four bytes. Each entry begins with a Pascal identifier and has a fixed preamble whose length depends on the subversion:

- subversion 1: 10 bytes after the identifier;
- subversion 2: 264 bytes after the identifier.

The preamble is followed by signed `top`, `left`, `bottom`, and `right` coordinates, a 16-bit depth, a compression byte, and pixel data. Width is `right - left`; height is `bottom - top`.

Depths 1, 8, and 16 are decoded. One-bit rows are independently byte-padded. Sixteen-bit samples are retained in `alpha16` and normalized into `alpha`. Compression `0` is raw; compression `1` stores a 16-bit byte count for every independently PackBits-compressed row.

Some Photoshop versions append eight bytes after the bitmap. AbrKit exposes all such bytes through `AbrSample.trailingData` instead of treating them as corruption.

### `desc`

The payload starts with descriptor version `16`, followed by one Photoshop Action Descriptor. The root `Brsh` list contains preset objects.

PsCore decodes every known descriptor OSType used by Photoshop: primitive numbers and strings, unit values, enumerations, nested objects, lists, object arrays, object references and all reference forms, aliases, paths, classes, and raw data. AbrKit maps common brush keys to typed domain models while retaining the complete `PsDescriptor` at each relevant level.

Typed brush engines and settings include:

- computed, sampled, bristle (`dBrush`), and erodible or airbrush (`dTips`) shapes;
- size, angle, roundness, count, scatter, opacity, flow, wetness, and mix dynamics;
- texture, dual brush, color dynamics, transfer, brush pose, noise, wet edges, and build-up;
- standard brush, mixer, smudge, eraser, smoothing, pressure override, and related tool options.

Unknown descriptor keys remain available through `rawDescriptor`, so their original type and value are not discarded.

### `patt`

Each embedded pattern is length-prefixed and normally four-byte aligned. Version 1 pattern records contain the Photoshop color mode, origin, Unicode name, Pascal identifier, an optional indexed palette, and a version 3 Virtual Memory Array List.

The virtual-memory list contains the overall bounds and present channel slots. AbrKit preserves all Photoshop color mode codes and decodes raw or PackBits channels at 1, 8, 16, and 32 bits. Unsupported channel extensions remain available as encoded bytes.

### `phry`

The payload is another version 16 Action Descriptor. Its `hierarchy` list records group or preset slots, including empty entries. AbrKit exposes typed names and identifiers plus each complete source descriptor.

## Error handling and resource limits

Every section, entry, descriptor, and row is parsed through a bounded reader. `AbrDecodeOptions` limits the input and section sizes, bitmap dimensions, retained decoded bitmap bytes, descriptor nesting and values, and collection counts.

Tolerant mode skips a malformed optional entry when its enclosing length makes recovery unambiguous. Strict mode rejects unknown or malformed data immediately. Neither mode silently invents values for an unsupported bitmap encoding.

## Reference implementations and specifications

- Adobe's Photoshop 6 file-format specification documents the fixed legacy brush records and the shared Photoshop descriptor and pattern structures.
- Adobe's current file-format specification documents Action Descriptors and Virtual Memory Array Lists used by the modern format.
- GIMP's reader documents and exercises the legacy records and modern `samp` layout.
- ag-psd provides an independently implemented modern section and Action Descriptor reader.

The modern `desc` key set remains extensible and is not publicly documented as a closed schema. Compatibility therefore depends on preserving unknown descriptors in addition to mapping fields observed in real Photoshop exports.
