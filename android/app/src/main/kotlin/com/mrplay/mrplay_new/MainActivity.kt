package com.mrplay.mrplay_new

import com.ryanheise.audioservice.AudioServiceActivity

/**
 * Extends AudioServiceActivity rather than FlutterActivity so audio_service can
 * attach the media playback service to this activity's FlutterEngine. Using a
 * plain FlutterActivity here compiles but silently breaks background audio:
 * the service ends up with a separate engine and no player.
 */
class MainActivity : AudioServiceActivity()
