import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import 'document_frame_stub.dart'
    if (dart.library.js_interop) 'document_frame_web.dart';

/// A4 at 96 dpi: the width the server lays each voucher design out for.
const double kA4Width = 794;
const double kA4Height = 1123;

/// The server's voucher HTML — the same document the website shows and the
/// PDF prints — in a native web view, scaled to its box.
///
/// [fit] `page` shows exactly page one (thumbnails); `content` grows to the
/// whole document. [interactive] lets the reader pinch-zoom and scroll (the
/// full-size preview); thumbnails ignore touches so the card receives them.
class VouchFlowDocumentView extends StatefulWidget {
  const VouchFlowDocumentView({
    super.key,
    required this.html,
    this.fit = VfDocumentFit.page,
    this.interactive = false,
    this.placeholderReplacements = const {},
  });

  final String html;
  final VfDocumentFit fit;
  final bool interactive;

  /// Text swapped into the HTML before it is shown — e.g. the logo
  /// placeholder the preview API prints for a logo only the device holds.
  final Map<String, String> placeholderReplacements;

  @override
  State<VouchFlowDocumentView> createState() => _VouchFlowDocumentViewState();
}

/// `page`: exactly page one, scaled to the width (thumbnails).
/// `content`: the whole document at its own height.
/// `fill`: fills its box and scrolls/zooms natively (full-size preview).
enum VfDocumentFit { page, content, fill }

class _VouchFlowDocumentViewState extends State<VouchFlowDocumentView> {
  /// The native web view. Web builds render an iframe instead (see
  /// document_frame_web.dart), so the controller only exists off the web.
  WebViewController? _controller;

  WebViewController _native() => _controller ??= _create();

  WebViewController _create() {
    final controller = WebViewController();
    // Android ignores the page's viewport width unless told to honour it, and
    // would squeeze the A4 sheet into the phone's width. With a wide viewport
    // and overview mode it lays the sheet out at A4 and zooms out to fit.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setUseWideViewPort(true);
    }
    return controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _measure(),
          // A document never navigates anywhere.
          onNavigationRequest: (r) =>
              r.url.startsWith('about:') || r.url.startsWith('data:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
  }

  double _contentHeight = kA4Height;
  String? _loaded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VouchFlowDocumentView old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html ||
        old.placeholderReplacements != widget.placeholderReplacements) {
      _load();
    }
  }

  String _prepared() {
    var html = widget.html;
    widget.placeholderReplacements.forEach(
      (k, v) => html = html.split(k).join(v),
    );
    // The server may print its own address as http://. Android's web view
    // refuses plain-http images (a browser quietly upgrades them), so the
    // company logo went missing: ask for every image over https.
    if (VfConfig.apiUrl.startsWith('https://')) {
      html = html.replaceAll('src="http://', 'src="https://');
    }
    // Lay the sheet out at A4 width and let the view scale it to fit.
    const viewport =
        '<meta name="viewport" content="width=794, user-scalable=yes">';
    if (html.contains('<head>')) {
      html = html.replaceFirst('<head>', '<head>$viewport');
    } else {
      html = '$viewport$html';
    }
    return html;
  }

  void _load() {
    final html = _prepared();
    if (html == _loaded) return;
    _loaded = html;
    if (kIsWeb) {
      if (mounted) setState(() {});
      return;
    }
    _native().loadHtmlString(html);
  }

  Future<void> _measure() async {
    if (widget.fit != VfDocumentFit.content) return;
    try {
      final result = await _native().runJavaScriptReturningResult(
        'document.documentElement.scrollHeight',
      );
      final h = double.tryParse('$result');
      if (h != null && h > 0 && mounted) {
        setState(() => _contentHeight = h < kA4Height ? kA4Height : h);
      }
    } catch (_) {
      // Height stays at one page.
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.isFinite
            ? box.maxWidth
            : MediaQuery.sizeOf(context).width;
        final scale = width / kA4Width;
        final height =
            (widget.fit == VfDocumentFit.page ? kA4Height : _contentHeight) *
            scale;
        final Widget view = kIsWeb
            ? platformDocumentFrame(
                html: _loaded ?? '',
                scale: scale,
                interactive: widget.interactive,
                fill: widget.fit == VfDocumentFit.fill,
              )
            : WebViewWidget(
                controller: _native(),
                // The full-size preview takes every touch, so a sideways drag
                // pans the sheet instead of being claimed by a parent.
                gestureRecognizers: widget.interactive
                    ? {
                        Factory<OneSequenceGestureRecognizer>(
                          EagerGestureRecognizer.new,
                        ),
                      }
                    : const {},
              );
        if (widget.fit == VfDocumentFit.fill) {
          return ColoredBox(color: Colors.white, child: view);
        }
        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: Colors.white,
            child: widget.interactive ? view : IgnorePointer(child: view),
          ),
        );
      },
    );
  }
}

/// A design in the gallery: a real miniature voucher, number, name and
/// description, Preview and Select — the web's template card.
class VouchFlowTemplateCard extends StatelessWidget {
  const VouchFlowTemplateCard({
    super.key,
    required this.number,
    required this.name,
    required this.description,
    required this.selected,
    required this.onPreview,
    this.onSelect,
    this.html,
    this.isCurrent = false,
    this.placeholderReplacements = const {},
    this.previewLabel = 'Preview',
    this.selectLabel = 'Select',
    this.selectedLabel = 'Selected',
    this.currentLabel = 'Current',
  });

  final int number;
  final String name;
  final String description;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onPreview;
  final VoidCallback? onSelect;
  final String? html;
  final Map<String, String> placeholderReplacements;
  final String previewLabel, selectLabel, selectedLabel, currentLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(VfSize.radiusXl),
        border: Border.all(
          color: selected ? t.primary : t.borderStrong,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: t.primary.withValues(alpha: .3),
                  blurRadius: 24,
                  spreadRadius: -12,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onPreview,
            child: Container(
              color: selected
                  ? Color.alphaBlend(
                      t.primary.withValues(alpha: .09),
                      t.surface2,
                    )
                  : t.surface2,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    child: html == null
                        ? AspectRatio(
                            aspectRatio: kA4Width / kA4Height,
                            child: ColoredBox(color: t.surface3),
                          )
                        : VouchFlowDocumentView(
                            html: html!,
                            placeholderReplacements: placeholderReplacements,
                          ),
                  ),
                  if (selected || isCurrent)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? t.primary : const Color(0xC70B1220),
                          borderRadius: BorderRadius.circular(
                            VfSize.radiusPill,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selected) ...[
                              const Icon(
                                PhosphorIconsBold.check,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              selected ? selectedLabel : currentLabel,
                              style: VfType.meta.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number.toString().padLeft(2, '0'),
                  style: VfType.eyebrow.copyWith(fontSize: 11, color: t.muted),
                ),
                const SizedBox(height: 2),
                Text(name, style: VfType.cardTitle.copyWith(color: t.text)),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: VfType.small.copyWith(color: t.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPreview,
                    icon: const Icon(PhosphorIconsRegular.eye, size: 16),
                    label: Text(
                      previewLabel,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
                if (onSelect != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: selected
                        ? TextButton.icon(
                            onPressed: null,
                            icon: Icon(
                              PhosphorIconsRegular.checkCircle,
                              size: 16,
                              color: t.primaryText,
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            label: Text(
                              selectedLabel,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: t.primaryText),
                            ),
                          )
                        : FilledButton(
                            onPressed: onSelect,
                            style: const ButtonStyle(
                              minimumSize: WidgetStatePropertyAll(Size(0, 40)),
                              padding: WidgetStatePropertyAll(
                                EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                            child: Text(
                              selectLabel,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
