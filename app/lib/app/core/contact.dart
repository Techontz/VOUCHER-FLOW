import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common.dart' show showToast;

/// VouchFlow's own addresses: `info` for general enquiries, `support` for
/// urgent help and customer care.
class VfContact {
  const VfContact._();

  static const info = 'info@vouchflow.co.tz';
  static const support = 'support@vouchflow.co.tz';

  /// Opens the email app on [address]. A device with no email app gets the
  /// address on its clipboard instead.
  static Future<void> email(String address, {String? subject}) async {
    final uri = Uri(
      scheme: 'mailto',
      path: address,
      query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: address));
      showToast('contact.copied'.tr, body: address);
    }
  }
}
