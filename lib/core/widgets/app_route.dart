import 'package:flutter/material.dart';

Route<T> smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _SmoothTransition(
      animation: animation,
      begin: const Offset(.06, 0),
      child: child,
    ),
  );
}

class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _SmoothTransition(
      animation: animation,
      begin: const Offset(.045, 0),
      child: child,
    );
  }
}

class _SmoothTransition extends StatefulWidget {
  const _SmoothTransition({
    required this.animation,
    required this.begin,
    required this.child,
  });

  final Animation<double> animation;
  final Offset begin;
  final Widget child;

  @override
  State<_SmoothTransition> createState() => _SmoothTransitionState();
}

class _SmoothTransitionState extends State<_SmoothTransition> {
  late CurvedAnimation _curve;
  late Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _createCurve();
  }

  void _createCurve() {
    _curve = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _updatePosition();
  }

  void _updatePosition() {
    _position = Tween<Offset>(begin: widget.begin, end: Offset.zero)
        .animate(_curve);
  }

  @override
  void didUpdateWidget(covariant _SmoothTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) {
      _curve.dispose();
      _createCurve();
    } else if (oldWidget.begin != widget.begin) {
      _updatePosition();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: SlideTransition(position: _position, child: widget.child),
  );
}
