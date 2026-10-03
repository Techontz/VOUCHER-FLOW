import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import 'auth_widgets.dart';

/// The sign-in screen's frame, built as an app rather than a web page: a
/// short brand header on the product's navy and blue, then the form on a
/// rounded sheet that fills the rest of the screen.
///
/// Used by both steps of signing in; only [card] changes.
class LoginFrame extends StatelessWidget {
  const LoginFrame({super.key, required this.card});

  final Widget card;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final media = MediaQuery.of(context);
    final keyboardUp = media.viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: t.chrome,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        media.padding.top + 8,
                        8,
                        0,
                      ),
                      child: const Row(
                        children: [Spacer(), AuthTools(onDark: true)],
                      ),
                    ),
                    AnimatedPadding(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.fromLTRB(
                        28,
                        keyboardUp ? 4 : 18,
                        28,
                        keyboardUp ? 20 : 36,
                      ),
                      child: const _Brand(),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: card,
                    ),
                  ),
                ),
              ),
              // The sheet's colour runs on to the foot of the screen.
              SliverFillRemaining(
                hasScrollBody: false,
                child: ColoredBox(
                  color: t.surface,
                  child: SizedBox(height: media.padding.bottom),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The mark in a glowing tile, the name and one short line.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: t.palette.primaryLight.withValues(alpha: .55),
                blurRadius: 32,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const VfBrandMark(size: 72),
        ),
        const SizedBox(height: 18),
        Text(
          'app.name'.tr,
          style: VfType.pageTitle.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'auth.tagline'.tr,
          textAlign: TextAlign.center,
          style: VfType.body.copyWith(
            fontSize: 14.5,
            color: Colors.white.withValues(alpha: .72),
          ),
        ),
      ],
    );
  }
}

/// Navy ground with two soft blooms of the company colour.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return CustomPaint(painter: _BackdropPainter(t.chrome, t.palette.primaryLight));
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.ground, this.accent);
  final Color ground, accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    void bloom(Offset c, double r, double a) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [accent.withValues(alpha: a), accent.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final w = size.width;
    bloom(Offset(w * .85, 40), math.max(w * .75, 260), .55);
    bloom(Offset(w * .05, 280), w * .6, .30);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.ground != ground || old.accent != accent;
}
