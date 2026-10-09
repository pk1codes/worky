import 'dart:io';

import 'package:flutter/material.dart';

class LocalThumb extends StatelessWidget {
  const LocalThumb({
    required this.path,
    required this.height,
    this.width,
    super.key,
  });

  final String path;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE7F2EE)),
      ),
    );
  }
}
