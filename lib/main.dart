import 'package:flutter/material.dart';
import 'package:songies/player/just_audio_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAudioPlatform();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Songies'))),
    ),
  );
}
