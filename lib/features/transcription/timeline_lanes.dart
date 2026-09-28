part of 'timeline_screen.dart';

/// One lane, as both the gutter and the track column need to see it.
class _TrackSpec {
  const _TrackSpec({
    required this.trackId,
    required this.kind,
    required this.height,
    required this.visible,
    required this.build,
    this.newTrack,
  });

  final String trackId;
  final TrackKind kind;
  final double height;
  final bool visible;
  final Widget Function() build;
  final int? newTrack;
}

/// A move under way: what is moving, where the finger started and is now,
/// and where it would all land.
class _Move {
  _Move({
    required this.moving,
    required this.origin,
    required this.scrollAt,
    required this.startRow,
    this.clipId,
  }) : pointer = origin;

  final Set<TimelineItem> moving;
  final Offset origin;
  final double scrollAt;
  final int startRow;
  Offset pointer;

  /// Set when a single clip is being moved: it reorders rather than moving
  /// on the time axis, and [clipDx] is how far its tile is drawn off.
  final String? clipId;
  double clipDx = 0;

  MovePlan? plan;
}

/// A resize under way, from one of an item's end grips.
class _Resize {
  _Resize({
    required this.item,
    required this.grip,
    required this.origin,
    required this.scrollAt,
  }) : pointer = origin;

  final TimelineItem item;
  final LayerGrip grip;
  final Offset origin;
  final double scrollAt;
  Offset pointer;
  LayerBounds? bounds;
}

/// The lane a drop below the last track would make: a dashed outline in the
/// outline's ink, holding the items where they would land.
class _DashedLane extends StatelessWidget {
  const _DashedLane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashPainter(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dash = 6.0;
    const gap = 4.0;
    void line(Offset from, Offset to) {
      final length = (to - from).distance;
      final step = (to - from) / length;
      for (var d = 0.0; d < length; d += dash + gap) {
        canvas.drawLine(
          from + step * d,
          from + step * math.min(d + dash, length),
          paint,
        );
      }
    }

    final r = Offset.zero & size;
    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A transcription's band: the stretch asked for. Its sentences are drawn
/// on it.
class _LayerBand extends StatelessWidget {
  const _LayerBand({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.30)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: _tileRadius,
        // Outlined only when selected, where the border carries a state
        // rather than drawing a frame.
        border: selected
            ? Border.all(color: theme.colorScheme.primary, width: 2)
            : null,
      ),
    );
  }
}

/// A text, an image or a translation line on its track: an icon, and its words
/// or a thumbnail.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.icon,
    required this.selected,
    this.label,
    this.image,
    this.direction,
    this.joinedLeft = false,
    this.joinedRight = false,
  });

  final IconData icon;
  final bool selected;
  final String? label;
  final String? image;
  final TextDirection? direction;
  final bool joinedLeft;
  final bool joinedRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = context.surface;
    final ink =
        selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final edge = surface.outlined
        ? BorderSide(color: surface.outline, width: 1)
        : BorderSide.none;
    final rule = BorderSide(
      color: surface.outlined ? surface.outline : appRuleColor(context),
      width: surface.outlined ? 1 : appRuleWidth(context),
    );
    final icon = WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xxs),
        child: Icon(this.icon, size: 14, color: ink),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        border: selected
            ? Border.all(color: surface.outline, width: 2)
            : Border(
                top: edge,
                bottom: edge,
                // The one line between neighbours is the right-hand one's.
                left: joinedLeft ? rule : edge,
                right: joinedRight ? BorderSide.none : edge,
              ),
        borderRadius: _tileRadius,
      ),
      clipBehavior: Clip.hardEdge,
      child: image != null
          ? Text.rich(
              TextSpan(children: [
                icon,
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Image.file(
                    File(image!),
                    height: 36,
                    cacheHeight: 96,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ]),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
            )
          // One run of text, icon included, so a block narrower than its
          // icon clips rather than overflowing.
          : Text.rich(
              TextSpan(children: [icon, TextSpan(text: label ?? '')]),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              textDirection: direction,
              style: theme.textTheme.labelSmall?.copyWith(color: ink),
            ),
    );
  }
}

/// An end grip: the chevron an item is resized from, the same on every kind.
class _EndGrip extends StatelessWidget {
  const _EndGrip({required this.atStart});

  final bool atStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: atStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        width: _layerGripWidth,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: _gripRadius(atStart: atStart),
        ),
        child: Icon(
          atStart ? Icons.chevron_left : Icons.chevron_right,
          size: _gripArrowSize,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
