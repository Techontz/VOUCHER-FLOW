import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:printing/printing.dart';

import '../core/theme.dart';

/// The voucher exactly as the server prints it — in the company's chosen
/// voucher template — rasterised from the same PDF that Print and Share use.
///
/// The native [fallback] is shown while the document loads and whenever the
/// server cannot provide it (the offline prototype, or a step that may view
/// but not print), so the screen is never empty.
class ServerVoucherDocument extends StatefulWidget {
  const ServerVoucherDocument({
    super.key,
    required this.load,
    required this.refreshKey,
    required this.fallback,
    this.title = '',
  });

  /// Heads the full-screen view (the voucher number).
  final String title;

  /// Fetches the PDF bytes.
  final Future<Uint8List> Function() load;

  /// Changes whenever the document would: status, signatures, files.
  final String refreshKey;

  final Widget fallback;

  @override
  State<ServerVoucherDocument> createState() => _ServerVoucherDocumentState();
}

class _ServerVoucherDocumentState extends State<ServerVoucherDocument> {
  List<Uint8List>? _pages;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant ServerVoucherDocument old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _render();
  }

  Future<void> _render() async {
    final generation = ++_generation;
    try {
      final bytes = await widget.load();
      final pages = <Uint8List>[];
      await for (final page in Printing.raster(bytes, dpi: 144)) {
        pages.add(await page.toPng());
      }
      if (!mounted || generation != _generation) return;
      setState(() => _pages = pages);
    } catch (_) {
      // Keep whatever was last rendered; with nothing, the fallback shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages == null || pages.isEmpty) {
      return widget.fallback;
    }

    final t = context.vf;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface2,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(VfSize.radiusL),
      ),
      child: Column(
        children: [
          for (var i = 0; i < pages.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: VfDoc.paper,
                borderRadius: BorderRadius.circular(VfSize.radiusXs),
                boxShadow: t.cardShadow,
              ),
              child: GestureDetector(
                // Tap a page to read it full screen, pinch to zoom.
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) =>
                        _FullDocument(pages: pages, title: widget.title),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VfSize.radiusXs),
                  child: Image.memory(
                    pages[i],
                    fit: BoxFit.fitWidth,
                    width: double.infinity,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FullDocument extends StatelessWidget {
  const _FullDocument({required this.pages, required this.title});

  final List<Uint8List> pages;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.vf;
    return Scaffold(
      backgroundColor: t.surface2,
      appBar: AppBar(
        backgroundColor: t.chrome,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(PhosphorIconsRegular.x, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: VfType.cardTitle.copyWith(color: Colors.white),
        ),
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: pages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => Image.memory(pages[i], fit: BoxFit.fitWidth),
        ),
      ),
    );
  }
}
