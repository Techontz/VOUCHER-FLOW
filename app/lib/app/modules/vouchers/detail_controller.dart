import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/session_service.dart';
import '../../data/services/voucher_repository.dart';
import '../../widgets/common.dart';
import 'detail_bits.dart';

/// Where a document comes from on a phone.
enum DocSource { camera, gallery, file }

/// A file picked on the phone, checked against the server's upload rules.
class PickedDoc {
  const PickedDoc(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The website's address, for the link a voucher is shared by.
const webOrigin = 'https://www.voucherflow.co.tz';

/// config('vouchflow.allowed_upload_mimes') by extension, and the size cap.
const _acceptedExtensions = {'pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'};
const _maxUploadBytes = 10 * 1024 * 1024;
const _maxFilesPerUpload = 10;

class VoucherDetailController extends GetxController {
  VoucherDetailController(this.voucherId);

  final int voucherId;
  final repo = Get.find<VoucherRepository>();
  final session = Get.find<SessionService>();

  final voucher = Rxn<Voucher>();
  final loading = true.obs;
  final error = RxnString();
  final forbidden = false.obs;

  /// Set while a workflow action is in flight.
  final busy = false.obs;

  /// Which file transfer is running: 'attach', 'print', 'pdf', 'ack-print-ID', 'ack-upload-ID', 'open-ID'.
  final working = RxnString();
  final commentField = TextEditingController();
  final commentText = ''.obs;

  /// The signer's own saved signature (a data URL), never anyone else's.
  final savedSignature = RxnString();

  @override
  void onInit() {
    super.onInit();
    commentField.addListener(() => commentText.value = commentField.text);
    load();
    repo
        .savedSignature()
        .then((value) => savedSignature.value = value)
        .catchError((_) => null);
  }

  @override
  void onClose() {
    commentField.dispose();
    super.onClose();
  }

  Future<void> load() async {
    if (voucher.value == null) loading.value = true;
    error.value = null;
    try {
      voucher.value = await repo.show(voucherId);
    } on ApiException catch (e) {
      forbidden.value = e.isForbidden;
      error.value = e.isForbidden ? 'state.notAuthorisedBody'.tr : e.message;
    } catch (_) {
      error.value = 'state.offline'.tr;
    } finally {
      loading.value = false;
    }
  }

  void _fail(Object e, String fallbackKey) {
    if (e is ApiException) {
      showToast(dt(fallbackKey), body: e.message, kind: ToastKind.bad);
    } else {
      showToast(dt(fallbackKey), body: 'state.offline'.tr, kind: ToastKind.bad);
    }
  }

  /// Runs one workflow transition. Returns the fresh voucher, or null when the
  /// server refused (the refusal is shown).
  Future<Voucher?> transition(Future<Voucher> Function() action) async {
    busy.value = true;
    try {
      final fresh = await action();
      voucher.value = fresh;
      session.refreshUnread();
      return fresh;
    } catch (e) {
      _fail(e, 'actionFailed');
      return null;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> sign({
    required String? signature,
    required bool save,
    String? comment,
  }) async {
    final v = await transition(
      () => repo.sign(
        voucherId,
        signature: signature,
        comment: comment,
        save: save && signature != null,
      ),
    );
    if (v == null) return false;
    if (save && signature != null) savedSignature.value = signature;
    showToast('msg.signed'.tr, body: dt('signedBody', {'number': v.number}));
    return true;
  }

  Future<bool> approve({String? signature, String? comment}) async {
    final v = await transition(
      () => repo.approve(voucherId, comment: comment, signature: signature),
    );
    if (v == null) return false;
    showToast(
      'msg.approved'.tr,
      body: dt('approvedBody', {
        'number': v.number,
        'status': v.statusLabel.toLowerCase(),
      }),
    );
    return true;
  }

  Future<bool> reject(String reason) async {
    final v = await transition(() => repo.reject(voucherId, reason));
    if (v == null) return false;
    showToast(
      'msg.rejected'.tr,
      body: dt('rejectedBody', {'number': v.number}),
      kind: ToastKind.bad,
    );
    return true;
  }

  Future<bool> requestChanges(String reason) async {
    final v = await transition(() => repo.requestChanges(voucherId, reason));
    if (v == null) return false;
    showToast('msg.changes'.tr, body: dt('changesBody'), kind: ToastKind.warn);
    return true;
  }

  Future<bool> submit({String? comment}) async {
    final v = await transition(() => repo.submit(voucherId, comment: comment));
    if (v == null) return false;
    showToast('msg.submitted'.tr, body: '${v.number} — ${v.statusLabel}');
    return true;
  }

  Future<bool> submitSigned({String? comment}) async {
    final v = await transition(
      () => repo.submitSigned(voucherId, comment: comment),
    );
    if (v == null) return false;
    showToast('msg.forwarded'.tr, body: '${v.number} — ${v.statusLabel}');
    return true;
  }

  Future<bool> cancel({String? comment}) async {
    final v = await transition(() => repo.cancel(voucherId, comment: comment));
    if (v == null) return false;
    showToast(dt('withdrawn'), body: v.number, kind: ToastKind.bad);
    return true;
  }

  /// Deletes the draft and leaves the page.
  Future<bool> deleteDraft() async {
    final number = voucher.value?.number ?? '';
    busy.value = true;
    try {
      await repo.delete(voucherId);
      showToast(dt('draftDeleted'), body: number, kind: ToastKind.warn);
      return true;
    } catch (e) {
      _fail(e, 'deleteFailed');
      return false;
    } finally {
      busy.value = false;
    }
  }

  /// Records one payment — all of the balance or part of it. Returns the
  /// voucher as it now stands and the payment just made.
  Future<(Voucher, VoucherPayment?)?> pay({
    required String method,
    String? reference,
    String? receivedBy,
    String? receiverIdNumber,
    String? comment,
    double? amount,
  }) async {
    final v = voucher.value;
    if (v == null) return null;
    final updated = await transition(
      () => repo.pay(
        voucherId,
        isCash: v.isCash,
        method: method,
        reference: reference,
        receivedBy: receivedBy,
        receiverIdNumber: receiverIdNumber,
        comment: comment,
        amount: amount,
      ),
    );
    if (updated == null) return null;
    return (updated, latestPayment(updated));
  }

  /// The payment just recorded: the one with the highest sequence.
  static VoucherPayment? latestPayment(Voucher v) => v.payments.isEmpty
      ? null
      : v.payments.reduce((a, b) => a.sequence >= b.sequence ? a : b);

  /// Whether to offer filing a signed copy: the company admin, anyone who can
  /// pay this voucher, or the cashier who made the payment. The server decides.
  bool canFileAcknowledgement(VoucherPayment payment) {
    final me = session.user.value;
    final v = voucher.value;
    if (me == null || v == null) return false;
    if (me.role == 'company_admin' || v.actions.pay) return true;
    return payment.paidById != null
        ? payment.paidById == me.id
        : payment.paidBy == me.name;
  }

  /// Prints the acknowledgement the receiver signs, in the reader's language.
  Future<void> printAcknowledgement(VoucherPayment payment) async {
    working.value = 'ack-print-${payment.id}';
    try {
      final bytes = await repo.acknowledgementPdf(
        voucherId,
        payment.id,
        lang: session.locale.value == 'sw' ? 'sw' : null,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'acknowledgement-${payment.reference.replaceAll('/', '-')}',
      );
    } catch (e) {
      _fail(e, 'ackPrintFailed');
    } finally {
      working.value = null;
    }
  }

  /// Picks documents from the camera, the gallery or files, applying the
  /// server's rules first. Shows why a file was refused.
  Future<List<PickedDoc>> pick(DocSource source, {bool multiple = true}) async {
    final picked = <PickedDoc>[];
    try {
      switch (source) {
        case DocSource.camera:
          final shot = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
            // A camera photo can be 5–12 MB; 2000px keeps a signed sheet
            // legible and well under the server's upload limit.
            maxWidth: 2000,
            maxHeight: 2000,
          );
          if (shot != null) {
            picked.add(PickedDoc(shot.name, await shot.readAsBytes()));
          }
        case DocSource.gallery:
          if (multiple) {
            for (final image in await ImagePicker().pickMultiImage(
              imageQuality: 85,
              // A camera photo can be 5–12 MB; 2000px keeps a signed sheet
              // legible and well under the server's upload limit.
              maxWidth: 2000,
              maxHeight: 2000,
            )) {
              picked.add(PickedDoc(image.name, await image.readAsBytes()));
            }
          } else {
            final image = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              // A camera photo can be 5–12 MB; 2000px keeps a signed sheet
              // legible and well under the server's upload limit.
              maxWidth: 2000,
              maxHeight: 2000,
            );
            if (image != null) {
              picked.add(PickedDoc(image.name, await image.readAsBytes()));
            }
          }
        case DocSource.file:
          final result = await FilePicker.platform.pickFiles(
            allowMultiple: multiple,
            type: FileType.custom,
            allowedExtensions: _acceptedExtensions.toList(),
            withData: true,
          );
          for (final f in result?.files ?? const <PlatformFile>[]) {
            if (f.bytes != null) picked.add(PickedDoc(f.name, f.bytes!));
          }
      }
    } catch (_) {
      return const [];
    }

    final ok = <PickedDoc>[];
    for (final doc in picked) {
      final ext = doc.name.split('.').last.toLowerCase();
      if (!_acceptedExtensions.contains(ext)) {
        showToast(
          dt('uploadFailed'),
          body: '${doc.name}: ${dt('fileWrongType')}',
          kind: ToastKind.bad,
        );
      } else if (doc.bytes.length > _maxUploadBytes) {
        showToast(
          dt('uploadFailed'),
          body: '${doc.name}: ${dt('fileTooLarge')} 10 MB',
          kind: ToastKind.bad,
        );
      } else if (ok.length < _maxFilesPerUpload) {
        ok.add(doc);
      }
    }
    return ok;
  }

  /// Adds receipts or supporting documents — also after approval and payment,
  /// when the voucher's details are locked but its paperwork is not.
  Future<void> attach(DocSource source) async {
    final docs = await pick(source);
    if (docs.isEmpty) return;
    working.value = 'attach';
    try {
      await repo.attach(voucherId, [
        for (final d in docs)
          http.MultipartFile.fromBytes('files[]', d.bytes, filename: d.name),
      ]);
      showToast(
        dt('attached'),
        body: dt('filesAdded', {'count': '${docs.length}'}),
      );
      await load();
    } catch (e) {
      _fail(e, 'uploadFailed');
    } finally {
      working.value = null;
    }
  }

  /// Files the receiver's signed copy against its payment.
  Future<void> uploadAcknowledgement(
    VoucherPayment payment,
    DocSource source,
  ) async {
    final docs = await pick(source, multiple: false);
    if (docs.isEmpty) return;
    working.value = 'ack-upload-${payment.id}';
    try {
      voucher.value = await repo.uploadAcknowledgement(
        voucherId,
        payment.id,
        http.MultipartFile.fromBytes(
          'file',
          docs.first.bytes,
          filename: docs.first.name,
        ),
      );
      showToast(
        dt('signedCopyFiled'),
        body: dt('signedCopyFiledBody', {'n': '${payment.sequence}'}),
      );
    } on ApiException catch (e) {
      showToast(
        dt('ackUploadFailed'),
        body: e.isForbidden ? dt('ackUploadForbidden') : e.message,
        kind: ToastKind.bad,
      );
    } catch (e) {
      _fail(e, 'ackUploadFailed');
    } finally {
      working.value = null;
    }
  }

  Future<Uint8List?> attachmentBytes(int attachmentId) async {
    try {
      return await repo.attachmentBytes(voucherId, attachmentId);
    } catch (e) {
      _fail(e, 'openFailed');
      return null;
    }
  }

  Future<void> postComment() async {
    final text = commentField.text.trim();
    if (text.isEmpty) return;
    try {
      await repo.comment(voucherId, text);
      commentField.clear();
      await load();
    } catch (e) {
      _fail(e, 'commentFailed');
    }
  }

  Future<void> printPdf() async {
    working.value = 'print';
    try {
      final bytes = await repo.pdf(voucherId);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: voucher.value?.number ?? 'voucher',
      );
    } catch (e) {
      _fail(e, 'pdfFailed');
    } finally {
      working.value = null;
    }
  }

  /// The PDF, handed to the phone's share sheet (save to files, mail, chat).
  Future<void> sharePdf() async {
    final v = voucher.value;
    final number = v?.number ?? 'voucher';
    working.value = 'pdf';
    try {
      final bytes = await repo.pdf(voucherId, download: true);
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            name: '$number.pdf',
            mimeType: 'application/pdf',
          ),
        ],
        subject: number,
        text: v?.purpose,
      );
    } on ApiException {
      // Until the server can render it, share the voucher's own particulars.
      if (v != null) {
        await Share.share(
          [
            '${v.number} · ${v.statusLabel}',
            '${v.purpose} — ${v.payee}',
            v.amountText,
            ?v.amountInWords,
            if (v.verificationCode != null)
              '${dt('verificationCode')}: ${v.verificationCode}',
          ].join('\n'),
          subject: v.number,
        );
      }
    } catch (e) {
      _fail(e, 'pdfFailed');
    } finally {
      working.value = null;
    }
  }

  /// The voucher's link on the website, as the web's Share button sends.
  Future<void> shareLink() async {
    final v = voucher.value;
    if (v == null) return;
    await Share.share(
      '${dt('shareText', {'number': v.number, 'purpose': v.purpose})}\n$webOrigin/vouchers/${v.id}',
      subject: v.number,
    );
  }

  /// A data URL for an image of a signature the signer picked.
  static String imageDataUrl(PickedDoc doc) {
    final ext = doc.name.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
    return 'data:$mime;base64,${base64Encode(doc.bytes)}';
  }
}
