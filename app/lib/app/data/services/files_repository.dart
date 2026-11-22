import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../models/erp_models.dart' show ErpPage;
import '../models/ops_models.dart';
import 'api_service.dart';

/// The Documents app's endpoints (backend routes/erp/crm.php, the
/// `module:documents` group under /erp/files): the folder browser, search,
/// expiring documents, one document, its bytes and uploads. A document the
/// caller may not open answers 404, like one that does not exist.
class FilesRepository {
  FilesRepository(this._api);

  final ApiService _api;

  static FilesRepository get to => Get.isRegistered<FilesRepository>()
      ? Get.find<FilesRepository>()
      : Get.put(FilesRepository(Get.find<ApiService>()), permanent: true);

  static const _base = '/erp/files';

  Future<Map<String, dynamic>> _map(String path, [Map<String, dynamic>? q]) async =>
      Map<String, dynamic>.from(await _api.get(path, q) as Map);

  /// One level of the library: [folderId] null is the top.
  Future<DmsListing> browse({int? folderId}) async =>
      DmsListing.fromJson(await _map('$_base/browse', {'folder_id': folderId, 'per_page': 200}));

  /// Every folder the caller may open, flat (for the upload form).
  Future<List<DmsFolder>> folders() async {
    final payload = await _map('$_base/folders');
    return ((payload['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => DmsFolder.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// A search over every document the caller may open.
  Future<ErpPage<DmsDocument>> search({String? q, String? type, int page = 1}) async => ErpPage.fromJson(
    await _map('$_base/documents', {'q': q, 'document_type': type, 'page': page, 'per_page': 30}),
    DmsDocument.fromJson,
  );

  /// Documents expiring within [days], and those already expired.
  Future<List<DmsDocument>> expiring({int days = 30}) async {
    final payload = await _map('$_base/expiring', {'days': days});
    return ((payload['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => DmsDocument.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// One document. [refresh] after a change, so it is not logged as another
  /// viewing.
  Future<DmsDocument> document(int id, {bool refresh = false}) async => DmsDocument.fromJson(
    Map<String, dynamic>.from((await _api.get('$_base/documents/$id', {'refresh': refresh ? 1 : null}) as Map)['data'] as Map),
  );

  /// The file itself (the current version unless [version] names another);
  /// the server logs the download.
  Future<List<int>> download(int id, {int? version}) =>
      _api.bytes('$_base/documents/$id/download', {'version': version});

  Future<DmsDocument> upload(DmsUploadDraft draft, {required String name, required List<int> bytes}) async {
    final r = await _api.upload(
      '$_base/documents',
      [http.MultipartFile.fromBytes('file', bytes, filename: name)],
      fields: draft.toFields(),
    );
    return DmsDocument.fromJson(Map<String, dynamic>.from((r as Map)['data'] as Map));
  }

  Future<void> addVersion(int id, {required String name, required List<int> bytes, String? note}) => _api.upload(
    '$_base/documents/$id/versions',
    [http.MultipartFile.fromBytes('file', bytes, filename: name)],
    fields: {if ((note ?? '').trim().isNotEmpty) 'note': note!.trim()},
  );
}
