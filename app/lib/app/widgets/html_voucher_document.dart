import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme.dart';
import 'vf/vf.dart';

/// The voucher exactly as the website shows it: the server's HTML in the
/// company's design, with its logo, signatures, stamps and the PAID /
/// REJECTED mark. Tap to read it full screen and pinch to zoom.
///
/// [fallback] shows while it loads and whenever the server cannot provide
/// the HTML (offline, or no permission), so the section is never empty.
class HtmlVoucherDocument extends StatefulWidget {
  const HtmlVoucherDocument({
    super.key,
    required this.load,
    required this.refreshKey,
    required this.fallback,
    this.title = '',
  });

  final Future<String> Function() load;
  final String refreshKey;
  final Widget fallback;
  final String title;

  @override
  State<HtmlVoucherDocument> createState() => _HtmlVoucherDocumentState();
}

class _HtmlVoucherDocumentState extends State<HtmlVoucherDocument> {
  String? _html;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant HtmlVoucherDocument old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _fetch();
  }

  Future<void> _fetch() async {
    final generation = ++_generation;
    try {
      final html = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _html = html;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  void _openFull(String html) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => VouchFlowPushedScaffold(
          title: widget.title,
          body: ColoredBox(
            color: context.vf.surface3,
            child: VouchFlowDocumentView(
              html: html,
              fit: VfDocumentFit.fill,
              interactive: true,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final html = _html;
    if (html == null) {
      return _failed ? widget.fallback : const _Loading();
    }
    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(VfSize.radiusXs),
            child: VouchFlowDocumentView(html: html, fit: VfDocumentFit.content),
          ),
          // The page itself ignores touches; this layer opens the reader.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: () => _openFull(html)),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsRegular.arrowsOut,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: kA4Width / kA4Height,
    child: Container(
      decoration: BoxDecoration(
        color: context.vf.surface3,
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
