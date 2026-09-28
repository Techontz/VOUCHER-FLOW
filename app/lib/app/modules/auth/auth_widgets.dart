import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme.dart';
import '../../data/services/session_service.dart';

/*
 * The pieces the public screens share, after the web's login-brand.tsx,
 * auth-frame.tsx and the sign-in / sign-up styles in vouchflow.css.
 */

/// The VouchFlow mark: a V drawn as a tick on a rounded square
/// (the web's `VouchFlowMark`).
class VfBrandMark extends StatelessWidget {
  const VfBrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _MarkPainter(context.vf.palette.primaryLight),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.fill);
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 36;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(.5 * s, .5 * s, 35 * s, 35 * s),
      Radius.circular(10 * s),
    );
    canvas.drawRRect(rect, Paint()..color = fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s
        ..color = Colors.white.withValues(alpha: .18),
    );
    final tick = Path()
      ..moveTo(10.5 * s, 12.5 * s)
      ..lineTo(17 * s, 24.5 * s)
      ..lineTo(26 * s, 10.5 * s);
    canvas.drawPath(
      tick,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.fill != fill;
}

/// Mark and name, as in the top-left of every public screen.
class VfWordmark extends StatelessWidget {
  const VfWordmark({super.key, this.size = 32, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VfBrandMark(size: size),
        SizedBox(width: size * .34),
        Flexible(
          child: Text(
            'app.name'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VfType.sectionTitle.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
              color: onDark ? Colors.white : t.text,
            ),
          ),
        ),
      ],
    );
  }
}

/// EN / SW and the appearance switch (the web's LanguageToggle + ThemeToggle).
/// [onDark] draws them for the navy hero of the sign-in screen.
class AuthTools extends StatelessWidget {
  const AuthTools({super.key, this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionService>();
    final t = context.vf;
    final segBg = onDark ? Colors.white.withValues(alpha: .10) : t.surface3;
    final onColour = onDark ? t.chrome : t.text;
    final offColour = onDark ? t.chromeText : t.muted;

    Widget seg(String code, String label) => Obx(() {
      final on = session.locale.value == code;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(VfSize.radiusM),
          onTap: on ? null : () => session.setLocale(code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 34),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: on
                  ? (onDark ? Colors.white : t.surface)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(VfSize.radiusM),
              boxShadow: on && !onDark ? t.cardShadow : null,
            ),
            child: Text(
              label,
              style: VfType.label.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: on ? onColour : offColour,
              ),
            ),
          ),
        ),
      );
    });

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'auth.language'.tr,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: segBg,
              borderRadius: BorderRadius.circular(VfSize.radiusL),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [seg('en', 'EN'), seg('sw', 'SW')],
            ),
          ),
        ),
        const SizedBox(width: 4),
        Obx(() {
          final dark = session.themeMode.value == ThemeMode.dark;
          return IconButton(
            tooltip: dark ? 'auth.toLight'.tr : 'auth.toDark'.tr,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: session.toggleTheme,
            icon: Icon(
              dark ? PhosphorIconsRegular.sun : PhosphorIconsRegular.moon,
              size: 22,
              color: onDark ? Colors.white : t.text2,
            ),
          );
        }),
      ],
    );
  }
}

/// A white (or dark-surface) card with the 4px accent strip inset along its
/// top edge — the web's `.vf-login-body`, `.vf-auth-card` and `.rg-card`.
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 28, 22, 24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.isDark ? t.border : Colors.transparent),
        boxShadow: t.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          Positioned(
            top: 0,
            left: 24,
            right: 24,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: t.primary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small capitalised label above a sign-in field (AGIZA's labels).
class AuthLabel extends StatelessWidget {
  const AuthLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: VfType.eyebrow.copyWith(
              fontSize: 12,
              letterSpacing: .6,
              color: t.muted,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// An inline text link in the accent colour (the web's `<Link>` in a line).
class AuthLink extends StatelessWidget {
  const AuthLink(this.label, {super.key, required this.onTap, this.size = 14});

  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Semantics(
      link: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VfSize.radiusXs),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Text(
              label,
              style: VfType.label.copyWith(
                fontSize: size,
                fontWeight: FontWeight.w600,
                color: t.primaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The eye button inside a password field.
class RevealButton extends StatelessWidget {
  const RevealButton({super.key, required this.revealed, required this.onTap});

  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: revealed ? 'auth.hidePassword'.tr : 'auth.showPassword'.tr,
    onPressed: onTap,
    icon: Icon(
      revealed ? PhosphorIconsRegular.eyeSlash : PhosphorIconsRegular.eye,
      size: 20,
      color: context.vf.muted,
    ),
  );
}

/// A text input styled like the web's `.input` (no label of its own).
class AuthInput extends StatelessWidget {
  const AuthInput({
    super.key,
    required this.controller,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
    this.invalid = false,
    this.enabled = true,
    this.inputFormatters,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String? placeholder;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final bool invalid;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      autocorrect: false,
      enableSuggestions: !obscure && keyboardType != TextInputType.emailAddress,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: VfType.body.copyWith(color: t.text),
      decoration: InputDecoration(
        hintText: placeholder,
        filled: true,
        fillColor: enabled ? t.inputBg : t.inputDisabled,
        suffixIcon: suffix,
        errorText: invalid ? '' : null,
        errorStyle: const TextStyle(height: 0, fontSize: 0),
      ),
    );
    return semanticLabel == null
        ? field
        : Semantics(label: semanticLabel, textField: true, child: field);
  }
}

/// Six boxes for a one-time code, backed by one field so paste, SMS/e-mail
/// autofill and the keyboard all work as they do on the web's six inputs.
class OtpField extends StatefulWidget {
  const OtpField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.invalid = false,
    this.autofocus = false,
    this.onSubmitted,
    this.focusNode,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool invalid;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final String? semanticLabel;

  @override
  State<OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<OtpField> {
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.removeListener(_changed);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    final code = widget.controller.text;
    final active = _focus.hasFocus ? code.length.clamp(0, 5) : -1;

    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox(
        height: 52,
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.enabled ? t.inputBg : t.inputDisabled,
                        borderRadius: BorderRadius.circular(VfSize.radiusL),
                        border: Border.all(
                          color: widget.invalid
                              ? t.dangerStrong
                              : i == active
                              ? t.ring
                              : t.inputBorder,
                          width: i == active ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        i < code.length ? code[i] : '',
                        style: VfType.figureS.copyWith(
                          color: t.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            // The real input, invisible, over the boxes.
            Positioned.fill(
              child: Opacity(
                opacity: 0.02,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onSubmitted: widget.onSubmitted,
                  showCursor: false,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.transparent,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame for the one-time-code screens and onboarding (the web's
/// AuthFrame): brand and tools on top, one focused card, the legal line.
class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.title,
    required this.child,
    this.kicker,
    this.sub,
    this.aside,
    this.bottomBar,
    this.onBack,
    this.scrollController,
  });

  final String? kicker;
  final String title;
  final String? sub;
  final Widget child;
  final Widget? aside;
  final Widget? bottomBar;

  /// Shown as a back arrow before the brand when set.
  final VoidCallback? onBack;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Scaffold(
      backgroundColor: t.background,
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        bottom: bottomBar == null,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            controller: scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (onBack != null)
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).backButtonTooltip,
                          onPressed: onBack,
                          icon: Icon(
                            PhosphorIconsRegular.arrowLeft,
                            color: t.text,
                          ),
                        ),
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: VfWordmark(),
                        ),
                      ),
                      const AuthTools(),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthCard(
                            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (kicker != null && kicker!.isNotEmpty) ...[
                                  Text(
                                    kicker!.toUpperCase(),
                                    style: VfType.eyebrow.copyWith(
                                      fontSize: 12,
                                      color: t.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Text(
                                  title,
                                  style: VfType.pageTitle.copyWith(
                                    fontSize: 24,
                                    color: t.text,
                                  ),
                                ),
                                if (sub != null && sub!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    sub!,
                                    style: VfType.body.copyWith(color: t.muted),
                                  ),
                                ],
                                const SizedBox(height: 22),
                                child,
                              ],
                            ),
                          ),
                          if (aside != null) ...[
                            const SizedBox(height: 16),
                            aside!,
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            PhosphorIconsRegular.shieldCheck,
                            size: 15,
                            color: t.muted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'auth.v.legal'.tr,
                            textAlign: TextAlign.center,
                            style: VfType.meta.copyWith(
                              fontSize: 13,
                              color: t.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
