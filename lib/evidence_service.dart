import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class EvidenceService {
  static String hashBytes(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

    

    static Future<String> saveEvidenceOffline({
    required Uint8List bytes,
    required String filenameHint,
    }) async {
    final dir = await getApplicationDocumentsDirectory();
    final evidencesDir = Directory('${dir.path}/offline_evidences');

    if (!await evidencesDir.exists()) {
        await evidencesDir.create(recursive: true);
    }

    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_$filenameHint';

    final file = File('${evidencesDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    return file.path;
    }

    static Future<Uint8List> readEvidenceOffline(String path) async {
    final file = File(path);
    return await file.readAsBytes();
    }

    static String hashString(String input) {
    return hashBytes(Uint8List.fromList(utf8.encode(input)));
    }


}
