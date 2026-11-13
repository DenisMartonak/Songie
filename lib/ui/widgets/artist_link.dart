import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../ytm/artist_lookup.dart';

/// The first name of an artist line such as "A, B", "A & B" or "A feat. B".
String firstArtistName(String line) =>
    line.split(RegExp(r', | & | feat\. ')).first.trim();

/// An artist line that opens the artist when tapped: [browseId] when known,
/// else the one found for [track], else Search for the first name. Its
/// gesture wins over the row it sits in; the rest of the row is unaffected.
/// [enabled] false shows plain text.
class ArtistLink extends ConsumerStatefulWidget {
  const ArtistLink({
    required this.text,
    this.browseId,
    this.track,
    this.enabled = true,
    this.style,
    this.maxLines = 1,
    super.key,
  });

  final String text;
  final String? browseId;
  final Track? track;
  final bool enabled;
  final TextStyle? style;
  final int maxLines;

  @override
  ConsumerState<ArtistLink> createState() => _ArtistLinkState();
}

class _ArtistLinkState extends ConsumerState<ArtistLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final text = Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: _hover && widget.enabled
          ? base.copyWith(decoration: TextDecoration.underline)
          : widget.style,
    );
    if (!widget.enabled || widget.text.trim().isEmpty) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openArtist(
          context,
          ref,
          browseId: widget.browseId,
          track: widget.track,
          name: firstArtistName(widget.text),
        ),
        child: text,
      ),
    );
  }
}
