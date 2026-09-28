import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import 'auth_widgets.dart';

/// The sign-in screen's frame, as the web lays it out on a phone
/// (components/login-brand.tsx under 960px): the navy hero, the sign-in card
/// overlapping its foot, then the detail — features, the route a voucher
/// takes, and the trust line — so the email field is one short screen away.
///
/// Used by both steps of signing in; only [card] changes.
class LoginFrame extends StatelessWidget {
  const LoginFrame({super.key, required this.card});

  final Widget card;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final ground = t.drawer;
    final navy = t.chrome;

    return Scaffold(
      backgroundColor: ground,
      body: LayoutBuilder(
        builder: (context, box) {
          final top = MediaQuery.paddingOf(context).top;
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: navy,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, top + 14, 12, 16),
                    child: _Hero(),
                  ),
                ),
                // The card rises 14px into the hero, as on the web.
                Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 14,
                      child: ColoredBox(color: navy),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: AuthCard(child: card),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ColoredBox(
                  color: navy,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      30,
                      20,
                      36 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: _Detail(wide: box.maxWidth > 520),
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

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final width = MediaQuery.sizeOf(context).width;
    final headline = (width * .074).clamp(28.0, 40.0);
    final line = VfType.pageTitle.copyWith(
      fontSize: headline,
      height: 1.1,
      letterSpacing: -.03 * headline,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: VfWordmark(size: 40, onDark: true),
              ),
            ),
            AuthTools(onDark: true),
          ],
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            'auth.eyebrow'.tr.toUpperCase(),
            style: VfType.eyebrow.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 3.6,
              color: t.chromeText,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${'auth.line1'.tr}\n'),
                TextSpan(text: '${'auth.line2'.tr}\n'),
                TextSpan(
                  text: 'auth.line3'.tr,
                  style: TextStyle(color: t.palette.textDark),
                ),
              ],
            ),
            style: line,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 14),
          child: Text(
            'auth.body'.tr,
            style: VfType.body.copyWith(
              fontSize: 14.5,
              height: 1.6,
              color: t.chromeText,
            ),
          ),
        ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.wide});

  final bool wide;

  static const _features = [
    (PhosphorIconsRegular.shieldCheck, 'auth.feat1', 'auth.feat1Sub'),
    (PhosphorIconsRegular.clockCounterClockwise, 'auth.feat2', 'auth.feat2Sub'),
    (PhosphorIconsRegular.flowArrow, 'auth.feat3', 'auth.feat3Sub'),
  ];

  static const _flow = [
    (PhosphorIconsRegular.notePencil, 'auth.flowCreate', 'auth.flowEmployee'),
    (PhosphorIconsRegular.signature, 'auth.flowSign', 'auth.flowHod'),
    (PhosphorIconsRegular.sealCheck, 'auth.flowApprove', 'auth.flowCeo'),
    (PhosphorIconsRegular.handCoins, 'auth.flowPay', 'auth.flowFinance'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final line = Colors.white.withValues(alpha: .10);
    final card = Colors.white.withValues(alpha: .05);
    final accent = t.palette.textDark;

    Widget stop(int i) {
      final (icon, action, role) = _flow[i];
      final state = i < 2 ? 'done' : (i == 2 ? 'current' : 'next');
      final hasConnector = wide ? i < 3 : i.isEven;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasConnector)
            Positioned(
              top: 18,
              left: 46,
              right: 6,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: state == 'done' ? t.primary : line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state == 'done'
                        ? t.primary
                        : Colors.white.withValues(alpha: .06),
                    border: Border.all(
                      color: state == 'done'
                          ? t.primary
                          : (state == 'current' ? accent : line),
                      width: state == 'current' ? 1.5 : 1,
                    ),
                    boxShadow: state == 'current'
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: .30),
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: state == 'done'
                        ? Colors.white
                        : (state == 'current' ? accent : t.chromeText),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  action.tr,
                  style: VfType.bodyStrong.copyWith(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                Text(
                  role.tr,
                  style: VfType.meta.copyWith(color: t.chromeMuted),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final cols = wide ? 4 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, title, sub) in _features)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: card,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.tr,
                          style: VfType.bodyStrong.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          sub.tr,
                          style: VfType.small.copyWith(color: t.chromeText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'auth.flowTitle'.tr.toUpperCase(),
          style: VfType.eyebrow.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 3.6,
            color: t.chromeText,
          ),
        ),
        const SizedBox(height: 16),
        for (var row = 0; row < 4 ~/ cols; row++)
          Padding(
            padding: EdgeInsets.only(bottom: row == 4 ~/ cols - 1 ? 0 : 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < cols; c++)
                  Expanded(child: stop(row * cols + c)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Text(
          'auth.flowNote'.tr,
          style: VfType.small.copyWith(fontSize: 13, color: t.chromeMuted),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
          decoration: BoxDecoration(
            color: card,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .10),
                  border: Border.all(color: accent.withValues(alpha: .22)),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  PhosphorIconsRegular.lockKey,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'auth.trustTitle'.tr,
                      style: VfType.bodyStrong.copyWith(
                        fontSize: 14.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'auth.trustBody'.tr,
                      style: VfType.small.copyWith(
                        fontSize: 13,
                        color: t.chromeText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
