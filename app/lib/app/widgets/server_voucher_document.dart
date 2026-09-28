import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  });

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

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.vfElev2,
        border: Border.all(color: context.vfLine),
        borderRadius: BorderRadius.circular(VfTheme.rLg),
      ),
      child: Column(
        children: [
          for (var i = 0; i < pages.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                pages[i],
                fit: BoxFit.fitWidth,
                width: double.infinity,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
