import 'package:flutter/material.dart';

// Small, reusable animations for every module. They run once (never loop) and
// are skipped when the phone's "remove animations" setting is on.

bool _reduced(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Fades and slides its child in when it first appears. Give list items an
/// increasing [index] to make them appear one after another.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final Offset offset;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = const Offset(0, 24),
  });
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  // The stagger is part of the curve (no timer), capped so the last items
  // never wait long.
  static const _run = 420;
  late final int _delay = 55 * widget.index.clamp(0, 8);
  late final _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _run + _delay),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(_delay / (_run + _delay), 1, curve: Curves.easeOutCubic),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _curve.value,
      child: Transform.translate(
        offset: widget.offset * (1 - _curve.value),
        child: child,
      ),
    ),
  );
}

/// Shrinks slightly while pressed, for cards and tiles that open something.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });
  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  void _set(bool down) {
    if (widget.onTap != null && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: _down ? .97 : 1,
    duration: const Duration(milliseconds: 120),
    curve: Curves.easeOut,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: widget.onTap,
        onHighlightChanged: _set,
        child: widget.child,
      ),
    ),
  );
}

/// A number that counts up (or down) to [value] when it changes.
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  const AnimatedCount(this.value, {super.key, this.style});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.toDouble()),
    duration: _reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 650),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => Text('${v.round()}', style: style),
  );
}

/// A progress bar that fills smoothly to [value] (0 to 1).
class AnimatedProgress extends StatelessWidget {
  final double value;
  final String? semanticsLabel;
  final Color? color;
  const AnimatedProgress(
    this.value, {
    super.key,
    this.semanticsLabel,
    this.color,
  });
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.clamp(0, 1)),
    duration: _reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 600),
    curve: Curves.easeOutCubic,
    builder: (context, v, _) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: v,
        minHeight: 7,
        color: color,
        semanticsLabel: semanticsLabel,
      ),
    ),
  );
}
