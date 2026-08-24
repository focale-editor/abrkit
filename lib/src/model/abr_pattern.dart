import 'package:pscore/pscore.dart';

/// Photoshop color model stored by an embedded ABR pattern.
typedef AbrColorMode = PsPatternColorMode;

/// One virtual-memory channel belonging to an embedded Photoshop pattern.
typedef AbrPatternChannel = PsPatternChannel;

/// One declared virtual-memory slot belonging to an embedded pattern.
typedef AbrPatternChannelSlot = PsPatternChannelSlot;

/// A rendered RGBA preview of an embedded pattern.
typedef AbrPatternImage = PsPatternImage;

/// A texture pattern embedded in the modern ABR `patt` section.
typedef AbrPattern = PsPattern;
