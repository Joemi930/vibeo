// Préparation des clips vidéo dans le navigateur.
//
// Seul point de contact entre Dart et l'API WebCodecs : le côté Dart ne
// manipule jamais de `File`, il reçoit un identifiant opaque (« handle ») et
// ne récupère à la fin que les octets du MP4 compressé et de la miniature.
// C'est ce qui évite de charger un fichier de plusieurs centaines de Mo dans
// la mémoire Dart — seul le résultat compressé (≤ 60 Mo) y transite.
//
// La compression réelle est faite par l'encodeur matériel du navigateur
// (WebCodecs), piloté par mediabunny (`mediabunny.min.js`, MPL-2.0). Aucun
// transcodage serveur : c'est la contrainte « budget 0 € » du projet.
//
// Toutes les fonctions renvoient un objet `{ status, ... }` plutôt que de
// lever une exception : la traduction d'une erreur JS vers Dart à travers
// `dart:js_interop` perd le message, et ces messages sont affichés à
// l'utilisateur.
(function () {
  'use strict';

  var MB = globalThis.Mediabunny;
  if (!MB) {
    console.error('Vibeo — mediabunny absent : la préparation vidéo est indisponible.');
    return;
  }

  /** Handles vivants : id -> { file, input, videoTrack }. */
  var handles = new Map();
  var nextHandle = 1;

  /** Input fichier unique, réutilisé à chaque sélection. */
  var fileInput = null;

  function ensureInput() {
    if (fileInput) return fileInput;
    fileInput = document.createElement('input');
    fileInput.type = 'file';
    fileInput.accept = 'video/mp4,video/quicktime,video/*';
    fileInput.multiple = false;
    fileInput.style.display = 'none';
    document.body.appendChild(fileInput);
    return fileInput;
  }

  /**
   * Ouvre le sélecteur de fichiers et analyse le clip choisi.
   *
   * Doit être appelée directement depuis un geste utilisateur, sinon le
   * navigateur refuse d'ouvrir la fenêtre.
   */
  async function pickVideo() {
    var input = ensureInput();
    input.value = '';

    var file = await new Promise(function (resolve) {
      var settled = false;
      function finish(value) {
        if (settled) return;
        settled = true;
        input.removeEventListener('change', onChange);
        input.removeEventListener('cancel', onCancel);
        resolve(value);
      }
      // `change` et `cancel` sont les deux évènements standard du sélecteur.
      // `cancel` est pris en charge par tous les navigateurs visés ; s'il
      // manque, la promesse reste simplement en attente et l'utilisateur peut
      // relancer la sélection.
      function onChange() {
        finish(input.files && input.files.length > 0 ? input.files[0] : null);
      }
      function onCancel() {
        finish(null);
      }
      input.addEventListener('change', onChange);
      input.addEventListener('cancel', onCancel);
      input.click();
    });

    if (!file) return { status: 'cancelled' };
    return probe(file);
  }

  /** Lit les métadonnées du clip et ouvre un handle. */
  async function probe(file) {
    var mbInput;
    try {
      mbInput = new MB.Input({
        formats: MB.ALL_FORMATS,
        source: new MB.BlobSource(file),
      });
      var videoTrack = await mbInput.getPrimaryVideoTrack();
      if (!videoTrack) {
        return {
          status: 'error',
          code: 'no_video_track',
          message: 'Ce fichier ne contient aucune piste vidéo.',
        };
      }

      var duration = await mbInput.computeDuration();
      var id = nextHandle++;
      handles.set(id, { file: file, input: mbInput, videoTrack: videoTrack });

      return {
        status: 'ok',
        handle: id,
        name: file.name,
        size: file.size,
        durationSeconds: Math.round(duration),
        width: videoTrack.displayWidth,
        height: videoTrack.displayHeight,
        decodable: await videoTrack.canDecode(),
      };
    } catch (error) {
      console.error('Vibeo — analyse du clip impossible', error);
      return {
        status: 'error',
        code: 'unreadable',
        message: 'Ce fichier vidéo est illisible ou son format n\'est pas reconnu.',
      };
    }
  }

  /**
   * Réencode le clip en MP4 / H.264, hauteur plafonnée à `maxHeight`.
   *
   * `quality` vaut 'medium' ou 'low' : l'appelant Dart réessaie en 'low' si le
   * premier résultat dépasse le plafond de taille.
   */
  async function compress(handleId, maxHeight, quality, onProgress) {
    var entry = handles.get(handleId);
    if (!entry) {
      return { status: 'error', code: 'stale_handle', message: 'Fichier introuvable. Choisis à nouveau ta vidéo.' };
    }

    try {
      // Jamais d'agrandissement : une source en 480p reste en 480p.
      var sourceHeight = entry.videoTrack.displayHeight || maxHeight;
      var targetHeight = Math.min(maxHeight, sourceHeight);
      // Les encodeurs H.264 exigent des dimensions paires.
      if (targetHeight % 2 !== 0) targetHeight -= 1;

      var output = new MB.Output({
        format: new MB.Mp4OutputFormat(),
        target: new MB.BufferTarget(),
      });

      var conversion = await MB.Conversion.init({
        input: entry.input,
        output: output,
        video: {
          height: targetHeight,
          codec: 'avc',
          bitrate: quality === 'low' ? MB.QUALITY_LOW : MB.QUALITY_MEDIUM,
        },
        audio: {
          codec: 'aac',
          bitrate: MB.QUALITY_MEDIUM,
        },
      });

      if (!conversion.isValid) {
        var reasons = (conversion.discardedTracks || [])
          .map(function (t) { return t.reason; })
          .join(', ');
        console.error('Vibeo — conversion invalide', conversion.discardedTracks);
        return {
          status: 'error',
          code: 'unsupported',
          message: 'Ce clip ne peut pas être préparé par ce navigateur (' + reasons + ').',
        };
      }

      if (onProgress) {
        conversion.onProgress = function (progress) {
          try {
            onProgress(progress);
          } catch (_) {
            // Un échec côté Dart ne doit pas interrompre l'encodage.
          }
        };
      }

      await conversion.execute();

      var buffer = output.target.buffer;
      if (!buffer) {
        return { status: 'error', code: 'empty_output', message: 'La préparation du clip a échoué.' };
      }

      return {
        status: 'ok',
        bytes: buffer,
        height: targetHeight,
      };
    } catch (error) {
      console.error('Vibeo — compression impossible', error);
      return {
        status: 'error',
        code: 'failed',
        message: 'La préparation du clip a échoué. Réessaie avec une autre vidéo.',
      };
    }
  }

  /** Extrait une image du clip et la renvoie en JPEG. */
  async function thumbnail(handleId, atSeconds) {
    var entry = handles.get(handleId);
    if (!entry) return { status: 'error', code: 'stale_handle' };

    try {
      var sink = new MB.CanvasSink(entry.videoTrack, { width: 640, fit: 'contain' });
      var frame = await sink.getCanvas(atSeconds);
      // Repli sur la toute première image si la position demandée est vide.
      if (!frame) frame = await sink.getCanvas(0);
      if (!frame) return { status: 'error', code: 'no_frame' };

      var blob = await canvasToJpeg(frame.canvas);
      if (!blob) return { status: 'error', code: 'no_frame' };
      return { status: 'ok', bytes: await blob.arrayBuffer() };
    } catch (error) {
      // Une miniature manquante ne doit jamais bloquer une publication.
      console.warn('Vibeo — extraction de la miniature impossible', error);
      return { status: 'error', code: 'failed' };
    }
  }

  function canvasToJpeg(canvas) {
    if (typeof canvas.convertToBlob === 'function') {
      return canvas.convertToBlob({ type: 'image/jpeg', quality: 0.82 });
    }
    return new Promise(function (resolve) {
      canvas.toBlob(resolve, 'image/jpeg', 0.82);
    });
  }

  /** Vrai si le navigateur sait encoder du H.264 — faux sur Firefox à ce jour. */
  async function canEncode() {
    try {
      return await MB.canEncodeVideo('avc', { width: 1280, height: 720 });
    } catch (_) {
      return false;
    }
  }

  /** Renvoie le fichier d'origine tel quel (repli quand l'encodage manque). */
  async function readOriginal(handleId) {
    var entry = handles.get(handleId);
    if (!entry) return { status: 'error', code: 'stale_handle' };
    try {
      return { status: 'ok', bytes: await entry.file.arrayBuffer() };
    } catch (error) {
      console.error('Vibeo — lecture du fichier impossible', error);
      return { status: 'error', code: 'failed' };
    }
  }

  /** Libère le handle : le fichier d'origine peut alors être ramassé. */
  function release(handleId) {
    handles.delete(handleId);
  }

  globalThis.vibeoMedia = {
    pickVideo: pickVideo,
    compress: compress,
    thumbnail: thumbnail,
    canEncode: canEncode,
    readOriginal: readOriginal,
    release: release,
  };
})();
