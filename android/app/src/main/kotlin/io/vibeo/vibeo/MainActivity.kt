package io.vibeo.vibeo

import com.ryanheise.audioservice.AudioServiceActivity

// Hérite d'AudioServiceActivity (et non de FlutterActivity) : exigé par
// audio_service pour que le service de lecture puisse se rattacher à
// l'application et survivre à la mise en arrière-plan (écran éteint).
class MainActivity : AudioServiceActivity()
