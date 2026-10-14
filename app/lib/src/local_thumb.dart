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
      child: const ColoredBox(
        color: Color(0xFFD9E6DC),
        child: Icon(Icons.image),
      ),
    );
  }
}
