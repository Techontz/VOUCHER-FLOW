import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme.dart';
import '../../widgets/vf/glass.dart';
import 'auth_widgets.dart';

/// The sign-in screen's frame, built as an app rather than a web page: the
/// glass wallpaper, a short brand header, then the form on a blurred glass
/// card.
///
/// Used by both steps of signing in; only [card] changes.
class LoginFrame extends StatelessWidget {
  const LoginFrame({super.key, required this.card});

  final Widget card;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardUp = media.viewInsets.bottom > 0;

    return VfWallpaper(
      child: Scaffold(
      backgroundColor: Colors.transparent,
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
                        children: [Spacer(), AuthTools()],
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
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    0,
                    14,
                    16 + media.padding.bottom,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: VfGlass(
                        strong: true,
                        borderRadius: BorderRadius.circular(
                          VfSize.radiusSheet + 4,
                        ),
                        padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
                        clip: false,
                        child: card,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
                color: t.primary.withValues(alpha: t.isDark ? .5 : .32),
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
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.1,
            color: t.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'auth.tagline'.tr,
          textAlign: TextAlign.center,
          style: VfType.body.copyWith(fontSize: 14.5, color: t.muted),
        ),
      ],
    );
  }
}

/// One extra bloom of the company colour behind the brand, over the
/// wallpaper.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return IgnorePointer(
      child: CustomPaint(
        painter: _BackdropPainter(t.primary, t.isDark ? .30 : .16),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.accent, this.strength);
  final Color accent;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
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
    bloom(Offset(w * .5, 150), math.max(w * .6, 220), strength);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) =>
      old.accent != accent || old.strength != strength;
}
