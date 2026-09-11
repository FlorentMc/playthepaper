import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// The seven letter cells: the centre hexagon and six around it.
class LettersHoneycomb extends StatelessWidget {
  const LettersHoneycomb({super.key, required this.center, required this.outer, required this.onLetter});

  final String center;
  final List<String> outer;

  /// Null makes the board read-only.
  final void Function(String letter)? onLetter;

  static const double gap = 7;

  /// The cells grow with the width on offer: 38 keeps six-letter words
  /// readable on a 320 px phone, 54 fills a 390 px phone edge to edge.
  static const double _minRadius = 38;
  static const double _maxRadius = 54;

  /// Reading order: top row, middle row (either side of the centre), bottom row.
  static const List<double> _anglesDeg = [240, 300, 180, 0, 120, 60];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - 2 * gap) / (3 * math.sqrt(3))
            : _maxRadius;
        final r = math.max(_minRadius, math.min(_maxRadius, available));
        final w = math.sqrt(3) * r;
        final h = 2 * r;
        final d = w + gap;
        final width = 2 * d + w;
        final height = 2 * d * math.sin(math.pi / 3) + h;

        Widget cell({required String letter, required bool isCenter, required double cx, required double cy}) =>
            Positioned(
              left: width / 2 + cx - w / 2,
              top: height / 2 + cy - h / 2,
              width: w,
              height: h,
              child: _HexCell(
                letter: letter,
                isCenter: isCenter,
                fontSize: (r * 0.82).roundToDouble(),
                onTap: onLetter == null ? null : () => onLetter!(letter),
              ),
            );

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                cell(letter: center, isCenter: true, cx: 0, cy: 0),
                for (var i = 0; i < outer.length && i < 6; i++)
                  cell(
                    letter: outer[i],
                    isCenter: false,
                    cx: d * math.cos(_anglesDeg[i] * math.pi / 180),
                    cy: d * math.sin(_anglesDeg[i] * math.pi / 180),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HexCell extends StatelessWidget {
  const _HexCell({required this.letter, required this.isCenter, required this.fontSize, required this.onTap});

  final String letter;
  final bool isCenter;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.gameColors;
    final theme = Theme.of(context);
    final fill = isCenter ? colors.misplaced : colors.cellHighlight;
    final ink = isCenter ? colors.onFeedback : theme.colorScheme.onSurface;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: isCenter ? 'centre letter $letter' : 'letter $letter',
      child: ExcludeSemantics(
        child: ClipPath(
          clipper: const _HexClipper(),
          child: Material(
            color: fill,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Text(letter, style: PaperTheme.display(size: fontSize, color: ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pointy-top hexagon filling its box.
class _HexClipper extends CustomClipper<Path> {
  const _HexClipper();

  @override
  Path getClip(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.height / 2;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (30 + 60 * i) * math.pi / 180;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldReclip(_HexClipper oldClipper) => false;
}
