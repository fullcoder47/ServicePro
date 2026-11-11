import '../../core/widgets/localized_text.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    // A single subtle entrance animation. A continuously repeating full-screen
    // gradient makes slow devices work harder while waiting for the network.
    controller = AnimationController(vsync: this,
      duration: const Duration(milliseconds: 700))..forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final v = Curves.easeInOut.transform(controller.value);
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + v * .4, -1),
                end: Alignment(1, 1 - v * .4),
                colors: [
                  colors.primary.withValues(alpha: .95),
                  colors.tertiaryContainer.withValues(alpha: .9),
                  colors.surface,
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: -80 + v * 24,
                  top: 80,
                  child: _Glow(size: 190, color: colors.onPrimary.withValues(alpha: .12)),
                ),
                Positioned(
                  right: -70,
                  bottom: 140 - v * 30,
                  child: _Glow(size: 240, color: colors.primaryContainer.withValues(alpha: .28)),
                ),
                Center(
                  child: Transform.scale(
                    scale: 0.96 + v * .04,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Card(
                          elevation: 0,
                          color: colors.surface.withValues(alpha: .86),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(30),
                                    gradient: LinearGradient(colors: [colors.primary, colors.tertiary]),
                                    boxShadow: [
                                      BoxShadow(
                                        blurRadius: 32,
                                        offset: const Offset(0, 16),
                                        color: colors.primary.withValues(alpha: .28),
                                      ),
                                    ],
                                  ),
                                  child: Transform.rotate(
                                    angle: math.sin(v * math.pi) * .08,
                                    child: Icon(Icons.home_repair_service_rounded, size: 56, color: colors.onPrimary),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text('ServicePro', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.5)),
                                const SizedBox(height: 8),
                                LocalizedText('Zayavka, chat, reklama va boshqaruv tizimi', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                                const SizedBox(height: 26),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(value: null, minHeight: 7, backgroundColor: colors.surfaceContainerHighest),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
