import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/crew_points.dart';

/// colors from the Crew Points promo video: dark leaf-green backdrop, lime
/// for daily points, gold for bonuses and the token, coral-red for losses
class PointsColors {
  PointsColors._();

  static const background = Color(0xFF14211A);
  static const backgroundTop = Color(0xFF1F3325);
  static const card = Color(0xFF1C2B21);
  static const cardBorder = Color(0xFF2E4434);
  static const lime = Color(0xFFB8F04A);
  static const gold = Color(0xFFF5C451);
  static const red = Color(0xFFF0605A);
  static const text = Colors.white;
  static const muted = Color(0xFFA9B8AC);

  static const _avatar = [
    Color(0xFFE5675F),
    Color(0xFFF2C14E),
    Color(0xFF6CC26F),
    Color(0xFF4F8EF2),
    Color(0xFFF29A4A),
    Color(0xFFA77BEA),
    Color(0xFF4CC9C0),
    Color(0xFFEC7FB0),
  ];

  /// a stable color per person, like the avatar circles in the video
  static Color avatarFor(String employeeId) {
    var hash = 0;
    for (final unit in employeeId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _avatar[hash % _avatar.length];
  }

  static Color forGroup(PointsGroup group, {int points = 0}) => switch (group) {
        PointsGroup.daily => lime,
        PointsGroup.bonus => gold,
        PointsGroup.penalty => red,
        PointsGroup.adjustment => points < 0 ? red : lime,
      };
}

/// the heavy italic display type from the video
TextStyle pointsDisplay(double size, {Color color = PointsColors.text}) =>
    TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      letterSpacing: -0.5,
      height: 1.0,
      color: color,
    );

/// small spaced-out caps label ("— HOW IT WORKS —")
TextStyle pointsEyebrow({Color color = PointsColors.lime}) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 2.2,
      color: color,
    );

String signedPoints(int points) => points > 0
    ? '+$points'
    : points < 0
        ? '−${-points}'
        : '0';

/// "— LABEL —" section header
class PointsEyebrow extends StatelessWidget {
  const PointsEyebrow(this.text, {this.color = PointsColors.lime, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 1.5, color: color.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text(text.toUpperCase(), style: pointsEyebrow(color: color)),
        const SizedBox(width: 8),
        Container(width: 14, height: 1.5, color: color.withValues(alpha: 0.6)),
      ],
    );
  }
}

/// the dark green, diagonal-striped backdrop with autumn leaves drifting
/// down it. Leaves are a fixed, seeded set so they don't jump on rebuild.
class FallingLeavesBackground extends StatefulWidget {
  const FallingLeavesBackground(
      {required this.child, this.leafCount = 26, super.key});

  final Widget child;
  final int leafCount;

  @override
  State<FallingLeavesBackground> createState() =>
      _FallingLeavesBackgroundState();
}

class _FallingLeavesBackgroundState extends State<FallingLeavesBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 30))
        ..repeat();
  late final List<_Leaf> _leaves = _Leaf.generate(widget.leafCount);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [PointsColors.backgroundTop, PointsColors.background],
              ),
            ),
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _LeavesPainter(
                  leaves: _leaves,
                  progress: reduceMotion ? null : _controller,
                ),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _Leaf {
  _Leaf(this.x, this.offset, this.speed, this.size, this.sway, this.spin,
      this.color);

  final double x, offset, speed, size, sway, spin;
  final Color color;

  static const _colors = [
    Color(0xFFD9A441),
    Color(0xFFC8643B),
    Color(0xFFE3B95C),
    Color(0xFFB4532F),
    Color(0xFF9C7A35),
  ];

  static List<_Leaf> generate(int count) {
    final random = math.Random(7);
    return List.generate(
      count,
      (_) => _Leaf(
        random.nextDouble(),
        random.nextDouble(),
        0.5 + random.nextDouble() * 1.0,
        7 + random.nextDouble() * 11,
        0.02 + random.nextDouble() * 0.05,
        random.nextDouble() * math.pi * 2,
        _colors[random.nextInt(_colors.length)],
      ),
    );
  }
}

class _LeavesPainter extends CustomPainter {
  _LeavesPainter({required this.leaves, this.progress})
      : super(repaint: progress);

  final List<_Leaf> leaves;
  final Animation<double>? progress;

  @override
  void paint(Canvas canvas, Size size) {
    // faint diagonal stripes
    final stripe = Paint()..color = Colors.white.withValues(alpha: 0.025);
    for (var x = -size.height; x < size.width; x += 90) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + 40, size.height)
        ..lineTo(x + 40 + size.height * 0.6, 0)
        ..lineTo(x + size.height * 0.6, 0)
        ..close();
      canvas.drawPath(path, stripe);
    }

    final t = progress?.value ?? 0.37;
    for (final leaf in leaves) {
      final fall = (leaf.offset + t * leaf.speed * 4) % 1.0;
      final y = -30 + fall * (size.height + 60);
      final x =
          (leaf.x + math.sin((fall * 6 + leaf.spin) * math.pi) * leaf.sway) *
              size.width;
      final paint = Paint()..color = leaf.color.withValues(alpha: 0.55);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(leaf.spin + fall * math.pi * 3);
      canvas.scale(
          1, 0.55 + 0.45 * math.cos(fall * math.pi * 8 + leaf.spin).abs());
      final s = leaf.size;
      final leafPath = Path()
        ..moveTo(-s, 0)
        ..quadraticBezierTo(0, -s * 0.75, s, 0)
        ..quadraticBezierTo(0, s * 0.75, -s, 0)
        ..close();
      canvas.drawPath(leafPath, paint);
      canvas.drawLine(
          Offset(-s, 0),
          Offset(s, 0),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.15)
            ..strokeWidth = 1);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LeavesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// a translucent rounded card with a colored left edge, like the point
/// cards in the video
class PointsCard extends StatelessWidget {
  const PointsCard({
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(14),
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent;
    return Container(
      decoration: BoxDecoration(
        color: highlighted
            ? PointsColors.lime.withValues(alpha: 0.12)
            : PointsColors.card.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? PointsColors.lime.withValues(alpha: 0.7)
              : PointsColors.cardBorder,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (accent != null) Container(width: 4, color: accent),
            Expanded(child: Padding(padding: padding, child: child)),
          ],
        ),
      ),
    );
  }
}

/// a "+1" / "−2" pill
class PointsPill extends StatelessWidget {
  const PointsPill(
      {required this.label,
      required this.color,
      this.struck = false,
      super.key});

  final String label;
  final Color color;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: struck ? Colors.transparent : color,
        borderRadius: BorderRadius.circular(999),
        border: struck ? Border.all(color: color.withValues(alpha: 0.5)) : null,
        boxShadow: struck
            ? null
            : [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          fontSize: 15,
          color:
              struck ? color.withValues(alpha: 0.6) : PointsColors.background,
          decoration: struck ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

/// round initials avatar in the person's color, with an optional ring
class PointsAvatar extends StatelessWidget {
  const PointsAvatar(
      {required this.participant, this.size = 36, this.ring, super.key});

  final PointsParticipant participant;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final color = PointsColors.avatarFor(participant.employeeId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border:
            ring == null ? null : Border.all(color: ring!, width: size * 0.07),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.4), blurRadius: size * 0.25)
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        participant.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}

/// a number that counts up (or down) to its value whenever it changes
class AnimatedPointsNumber extends StatelessWidget {
  const AnimatedPointsNumber({
    required this.value,
    required this.style,
    this.prefix = '',
    this.decimals = 0,
    this.duration = const Duration(milliseconds: 1400),
    super.key,
  });

  final double value;
  final TextStyle style;
  final String prefix;
  final int decimals;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) =>
          Text('$prefix${animated.toStringAsFixed(decimals)}', style: style),
    );
  }
}

/// the gold "1" challenge-token coin, gently pulsing while it's unspent
class ChallengeCoin extends StatefulWidget {
  const ChallengeCoin({this.size = 64, this.spent = false, super.key});

  final double size;
  final bool spent;

  @override
  State<ChallengeCoin> createState() => _ChallengeCoinState();
}

class _ChallengeCoinState extends State<ChallengeCoin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (!widget.spent) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ChallengeCoin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spent) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glow = widget.spent ? 0.0 : 0.25 + 0.35 * _controller.value;
        return Opacity(
          opacity: widget.spent ? 0.35 : 1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [
                  Color(0xFFFFE08A),
                  Color(0xFFE8A92E),
                  Color(0xFFB57A14)
                ],
                stops: [0, 0.6, 1],
              ),
              border: Border.all(
                  color: const Color(0xFFFFE9A8), width: size * 0.05),
              boxShadow: [
                BoxShadow(
                  color: PointsColors.gold.withValues(alpha: glow),
                  blurRadius: size * 0.6,
                  spreadRadius: size * 0.05,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text('1',
                style:
                    pointsDisplay(size * 0.55, color: const Color(0xFF7A4E05))),
          ),
        );
      },
    );
  }
}

/// slides and fades a child in after [delay] — for staggered list entry
class PointsEntrance extends StatelessWidget {
  const PointsEntrance(
      {required this.child, this.delay = Duration.zero, super.key});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final total = const Duration(milliseconds: 450) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (context, t, child) {
        final local = Curves.easeOutCubic
            .transform(((t - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(
          opacity: local,
          child: Transform.translate(
              offset: Offset(0, 18 * (1 - local)), child: child),
        );
      },
      child: child,
    );
  }
}

/// a "+3" that floats up and fades out over the points total, shown when
/// someone's total went up since they last opened the page
class FloatingGain extends StatelessWidget {
  const FloatingGain({required this.gain, super.key});

  final int gain;

  @override
  Widget build(BuildContext context) {
    final color = gain >= 0 ? PointsColors.lime : PointsColors.red;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 2200),
        curve: Curves.easeOut,
        builder: (context, t, _) {
          final fade = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -60 * t),
              child: Transform.scale(
                scale: 0.6 +
                    0.6 * Curves.elasticOut.transform(math.min(1, t * 1.6)),
                child: Text(signedPoints(gain),
                    style: pointsDisplay(34, color: color)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// a one-shot burst of leaf-colored confetti
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
    ..forward();
  final _random = math.Random();
  late final _pieces = List.generate(
    40,
    (_) => (
      angle: _random.nextDouble() * math.pi * 2,
      speed: 120 + _random.nextDouble() * 220,
      size: 4 + _random.nextDouble() * 5,
      color: [
        PointsColors.lime,
        PointsColors.gold,
        const Color(0xFFE5675F),
        Colors.white
      ][_random.nextInt(4)],
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_pieces, _controller.value),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<({double angle, double speed, double size, Color color})> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.35);
    for (final piece in pieces) {
      final distance = piece.speed * Curves.easeOut.transform(t);
      final gravity = 260 * t * t;
      final position = center +
          Offset(math.cos(piece.angle) * distance,
              math.sin(piece.angle) * distance + gravity);
      final paint = Paint()
        ..color = piece.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(piece.angle + t * 10);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: piece.size, height: piece.size * 0.5),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
