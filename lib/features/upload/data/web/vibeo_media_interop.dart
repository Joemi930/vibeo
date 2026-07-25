/// Pont Dart ↔ `web/js/vibeo_media.js`.
///
/// Ce fichier n'est compilé que pour le web : il n'est importé que par les
/// implémentations `*_web.dart`, elles-mêmes sélectionnées par import
/// conditionnel.
///
/// Chaque fonction JavaScript renvoie un objet `{ status, ... }` au lieu de
/// lever une exception : le passage d'une erreur JS vers Dart perd le message,
/// et ces messages sont montrés à l'utilisateur.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Résultat d'une sélection de fichier.
extension type PickResult._(JSObject _) implements JSObject {
  external String get status;
  external String? get code;
  external String? get message;
  external int? get handle;
  external String? get name;
  external int? get size;
  external int? get durationSeconds;
  external int? get width;
  external int? get height;
  external bool? get decodable;
}

/// Résultat d'une opération renvoyant des octets (clip compressé, miniature).
extension type BytesResult._(JSObject _) implements JSObject {
  external String get status;
  external String? get code;
  external String? get message;
  external JSArrayBuffer? get bytes;
  external int? get height;
}

extension type _VibeoMedia._(JSObject _) implements JSObject {
  external JSPromise<PickResult> pickVideo();
  external JSPromise<BytesResult> compress(
    int handle,
    int maxHeight,
    String quality,
    JSFunction? onProgress,
  );
  external JSPromise<BytesResult> thumbnail(int handle, double atSeconds);
  external JSPromise<JSBoolean> canEncode();
  external JSPromise<BytesResult> readOriginal(int handle);
  external void release(int handle);
}

/// Vrai si `web/js/vibeo_media.js` a bien été chargé.
///
/// Faux uniquement si le script manque (déploiement incomplet, blocage réseau) :
/// l'appelant doit alors afficher un message plutôt que planter.
bool get isMediaBridgeReady => globalContext.has('vibeoMedia');

_VibeoMedia get _bridge => globalContext['vibeoMedia'] as _VibeoMedia;

Future<PickResult> pickVideoFile() => _bridge.pickVideo().toDart;

Future<BytesResult> compressVideoFile({
  required int handle,
  required int maxHeight,
  required String quality,
  void Function(double progress)? onProgress,
}) {
  return _bridge.compress(handle, maxHeight, quality, onProgress?.toJS).toDart;
}

Future<BytesResult> grabThumbnail({
  required int handle,
  required double atSeconds,
}) => _bridge.thumbnail(handle, atSeconds).toDart;

Future<bool> canEncodeH264() async => (await _bridge.canEncode().toDart).toDart;

Future<BytesResult> readOriginalFile(int handle) =>
    _bridge.readOriginal(handle).toDart;

void releaseHandle(int handle) => _bridge.release(handle);

/// Convertit l'`ArrayBuffer` renvoyé par JavaScript en octets Dart.
///
/// Faite ici pour que le reste du code n'ait pas à importer `dart:js_interop`.
Uint8List? bytesOf(BytesResult result) {
  final buffer = result.bytes;
  if (buffer == null) return null;
  return Uint8List.view(buffer.toDart);
}
