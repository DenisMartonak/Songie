import 'package:flutter/material.dart';

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) => Center(child: Text('Playlist $id'));
}
