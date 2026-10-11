import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'langs.dart';

class Speaker {
  static final FlutterTts _tts = FlutterTts();
  static final AudioPlayer _clips = AudioPlayer();

  static Future<void> say(String? lang, String text) async {
    if (kIsWeb || lang == null || text.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(kVoice[lang] ?? 'en-IN');
      await _tts.speak(text);
    } catch (_) {}
  }

  static Future<void> clip(String code) async {
    if (kIsWeb) return;
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

class NetImage extends StatelessWidget {
  const NetImage({
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheLogical,
    this.error,
    super.key,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double? cacheLogical;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return error ?? const SizedBox.shrink();
    final cache = cacheLogical == null ? null : imageCacheWidth(context, cacheLogical!);
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cache,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      errorWidget: (_, _, _) => error ?? const SizedBox.shrink(),
    );
  }
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
    this.compact = false,
    this.stretch = false,
    this.extent,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? label;
  final Color? color;
  final bool filled;
  final bool compact;
  final bool stretch;
  final double? extent;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : (color ?? const Color(0xFF16332C));
    final tight = compact || label == null;
    final side = extent;
    final iconPx = side == null ? 40.0 : side * 0.75;
    final button = IconButton(
      onPressed: onTap,
      iconSize: iconPx,
      style: IconButton.styleFrom(
        minimumSize: side == null
            ? Size(stretch ? 0 : (tight ? 72 : 64), 64)
            : Size(side, side),
        fixedSize: side != null
            ? Size(side, side)
            : (tight && !stretch ? const Size(72, 64) : null),
        padding: EdgeInsets.symmetric(horizontal: tight ? 4 : 10, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: filled
            ? (color ?? const Color(0xFF0F6E56))
            : const Color(0xFFE7F2EE),
        foregroundColor: fg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: tight
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: iconPx),
                if (label != null)
                  stretch
                      ? SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label!,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1,
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1,
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconPx),
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1,
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
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
    this.uniform = false,
    super.key,
  });

  final String code;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final double? extent;
  final bool uniform;

  @override
  Widget build(BuildContext context) {
    const mint = Color(0xFFE7F2EE);
    const ink = Color(0xFF16332C);
    const brand = Color(0xFF0F6E56);
    final color = uniform ? brand : Color(kLangColor[code] ?? 0xFF0F6E56);
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
          height: side ?? double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: uniform
                ? (selected ? brand : mint)
                : color.withValues(alpha: selected ? 1 : 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: uniform ? (selected ? brand : mint) : color,
              width: selected && !uniform ? 4 : 1,
            ),
          ),
          child: Text(
            kAutonym[code] ?? code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: extent != null ? 11 : (compact ? 14 : 22),
              color: selected ? Colors.white : ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
