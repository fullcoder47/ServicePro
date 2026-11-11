import 'package:flutter/material.dart';

class PickedVideoPreview extends StatelessWidget {
  const PickedVideoPreview({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Text('Videoni yuborgandan keyin ilova ichida ko‘rishingiz mumkin.'),
  );
}
