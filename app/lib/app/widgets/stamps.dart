import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'common.dart';

/// Official marks for the voucher document.
///
/// These stand in for the rubber stamps a finance office actually uses, so
/// they are drawn as ink on paper: a ruled frame, tracked capitals, and the
/// moment the act happened. They are deliberately plain — a stamp that looks
/// decorative reads as fake.
enum StampKind { signed, approved, paid, rejected, returned }

extension StampInk on StampKind {
  Color get colour => switch (this) {
    StampKind.signed => const Color(0xFF1F3A8A),
    StampKind.approved => const Color(0xFF0F7A54),
    StampKind.paid => const Color(0xFFA3183A),
    StampKind.rejected => const Color(0xFFA3183A),
    StampKind.returned => const Color(0xFF8A5A00),
  };

  String get word => switch (this) {
    StampKind.signed => 'SIGNED',
    StampKind.approved => 'APPROVED',
    StampKind.paid => 'PAID',
    StampKind.rejected => 'REJECTED',
    StampKind.returned => 'RETURNED',
  };
}

class Stamp extends StatelessWidget {
  const Stamp({
    super.key,
    required this.kind,
    this.date,
    this.reference,
    this.tilt = -0.07,
    this.scale = 1,
  });

  final StampKind kind;
  final String? date, reference;

  /// Radians. A stamp is pressed by hand; a perfectly square one looks printed.
  final double tilt;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final colour = kind.colour;
    final meta = [
      reference,
      date,
    ].where((v) => v != null && v.isNotEmpty).join(' · ');

    return Transform.rotate(
      angle: tilt,
      child: Transform.scale(
        scale: scale,
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 3),
          decoration: BoxDecoration(
            border: Border.all(color: colour, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kind.word,
                style: TextStyle(
                  fontFamily: VfTheme.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.4,
                  height: 1.1,
                  color: colour,
                ),
              ),
              if (meta.isNotEmpty)
                Text(
                  meta,
                  style: TextStyle(
                    fontFamily: VfTheme.fontFamily,
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .4,
                    height: 1.3,
                    color: colour,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One column of the authorisation band: who did it, their mark, their
/// signature and when. Every voucher carries the same four columns so the
/// document reads identically whatever stage it has reached.
class AuthorisationBlock extends StatelessWidget {
  const AuthorisationBlock({
    super.key,
    required this.caption,
    this.name,
    this.title,
    this.date,
    this.signature,
    this.stamp,
    this.reference,
    this.note,
    this.emphasis = false,
  });

  final String caption;
  final String? name, title, date, signature, reference, note;
  final StampKind? stamp;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final done = name != null && date != null;
    final bytes = decodeSignature(signature);

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: emphasis && done
              ? const Color(0xFFC3D4F5)
              : const Color(0xFFE2E7EF),
        ),
        borderRadius: BorderRadius.circular(6),
        color: emphasis && done
            ? const Color(0xFFF6F9FF)
            : const Color(0xFFFCFDFF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(caption.toUpperCase(), style: VfDoc.label),
          SizedBox(
            height: 46,
            child: Center(
              child: done
                  // The column is narrow; the whole mark shrinks to fit rather
                  // than any part of it spilling over the frame.
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (bytes != null)
                            Image.memory(
                              bytes,
                              height: 26,
                              fit: BoxFit.contain,
                            ),
                          if (bytes != null && stamp != null)
                            const SizedBox(width: 5),
                          if (stamp != null)
                            Stamp(
                              kind: stamp!,
                              date: date,
                              reference: reference,
                              scale: .74,
                            ),
                          if (bytes == null && stamp == null)
                            Text(
                              name!,
                              style: const TextStyle(
                                fontFamily: VfTheme.fontFamily,
                                fontStyle: FontStyle.italic,
                                fontSize: 15,
                                color: VfDoc.ink,
                              ),
                            ),
                        ],
                      ),
                    )
                  : Text(
                      (note ?? 'Pending').toUpperCase(),
                      style: const TextStyle(
                        fontFamily: VfTheme.fontFamily,
                        fontSize: 8,
                        letterSpacing: .8,
                        color: Color(0xFFB3BCCD),
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.only(top: 5),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFD7DDE8))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name ?? '—', style: VfDoc.strong.copyWith(fontSize: 9.5)),
                if (title != null && title!.isNotEmpty)
                  Text(title!, style: VfDoc.mutedStyle.copyWith(fontSize: 8.5)),
                if (date != null)
                  Text(date!, style: VfDoc.faintStyle.copyWith(fontSize: 8.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
