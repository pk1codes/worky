import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'langs.dart';

class Speaker {
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _clips = AudioPlayer();

  static Future<void> say(String? lang, String text) async {
    if (lang == null || text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(kVoice[lang] ?? 'en-IN');
      await _tts.speak(text);
    } catch (_) {}
  }

  static Future<void> clip(String code) async {
    try {
      await _clips.stop();
      await _clips.play(AssetSource('lang/$code.mp3'));
    } catch (_) {
      await say(code, kAutonym[code] ?? code);
    }
  }
}

int imageCacheWidth(BuildContext context, double logical) {
  final width = (logical * MediaQuery.devicePixelRatioOf(context)).round();
  return width < 1 ? 1 : width;
}

class Paged extends StatelessWidget {
  const Paged({required this.page, required this.child, super.key});

  final int page;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (kDebugMode)
          const Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(child: SizedBox.shrink()),
          ),
        if (kDebugMode)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Text(
                '$page',
                style: const TextStyle(color: Color(0x66000000), fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class BigIcon extends StatelessWidget {
  const BigIcon({
    required this.icon,
    required this.onTap,
    this.label,
    this.color,
    this.filled = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? label;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : (color ?? const Color(0xFF16332C));
    final button = IconButton(
      onPressed: onTap,
      iconSize: 40,
      style: IconButton.styleFrom(
        fixedSize: const Size(72, 72),
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: filled ? (color ?? const Color(0xFF0F6E56)) : null,
        foregroundColor: fg,
      ),
      icon: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40),
          if (label != null)
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, height: 1, color: fg),
            ),
        ],
      ),
    );
    if (label == null) return button;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: button,
    );
  }
}

class LangTile extends StatelessWidget {
  const LangTile({
    required this.code,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.extent,
    super.key,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final double? extent;

  @override
  Widget build(BuildContext context) {
    final color = Color(kLangColor[code] ?? 0xFF0F6E56);
    final side = extent ?? (compact ? 72.0 : null);
    return Semantics(
      button: true,
      label: kAutonym[code],
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: side ?? double.infinity,
          height: side ?? 96,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 1 : 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: selected ? 4 : 1),
          ),
          child: Text(
            kAutonym[code] ?? code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: extent != null ? 11 : (compact ? 14 : 22),
              color: selected ? Colors.white : const Color(0xFF16332C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
