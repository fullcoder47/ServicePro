import 'localized_text.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class MediaViewerDialog extends StatelessWidget {
  const MediaViewerDialog({super.key, required this.title, required this.body, required this.mediaUrls, required this.mediaTypes, this.actionUrl, this.actionLabel = 'Batafsil'});

  final String title;
  final String body;
  final List<String> mediaUrls;
  final List<String> mediaTypes;
  final String? actionUrl;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [colors.primaryContainer, colors.surfaceContainerHighest]),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_rounded),
                      const SizedBox(width: 10),
                      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                if (body.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(body, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                if (mediaUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        for (var i = 0; i < mediaUrls.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MediaBlock(
                              url: mediaUrls[i],
                              type: i < mediaTypes.length ? mediaTypes[i] : '',
                            ),
                          ),
                      ],
                    ),
                  ),
                if (actionUrl != null && actionUrl!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => openAdvertisementLink(context, actionUrl!),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: Text(actionLabel.trim().isEmpty ? 'Batafsil' : actionLabel,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ad URLs are external HTTPS/HTTP destinations, never app routes or scripts.
Future<void> openAdvertisementLink(BuildContext context, String value) async {
  final raw = value.trim();
  final uri = Uri.tryParse(raw);
  if (raw.length > 2048 || raw.contains(RegExp(r'\s')) || uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reklama havolasi noto‘g‘ri.')),
      );
    }
    return;
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Havolani ochib bo‘lmadi.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Havolani ochishda xatolik.')),
      );
    }
  }
}

class _MediaBlock extends StatelessWidget {
  const _MediaBlock({required this.url, required this.type});
  final String url;
  final String type;

  bool get isVideo {
    final clean = url.toLowerCase().split('?').first;
    return type == 'video' || clean.endsWith('.mp4') || clean.endsWith('.mov') || clean.endsWith('.webm') || clean.endsWith('.m4v');
  }

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return _InlineVideo(url: url);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: InteractiveViewer(
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null ? child : const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
          errorBuilder: (_, __, ___) => const SizedBox(height: 180, child: Center(child: Icon(Icons.broken_image_rounded, size: 44))),
        ),
      ),
    );
  }
}

class _InlineVideo extends StatefulWidget {
  const _InlineVideo({required this.url});
  final String url;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  VideoPlayerController? controller;
  bool ready = false;
  bool requested = false;
  String? error;

  Future<void> _loadVideo() async {
    if (requested) return;
    final uri = Uri.tryParse(widget.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => error = 'Video manzili noto‘g‘ri.');
      return;
    }
    setState(() => requested = true);
    final player = VideoPlayerController.networkUrl(uri);
    controller = player;
    try {
      await player.initialize();
      if (!mounted) return;
      setState(() => ready = true);
      await player.play();
    } catch (_) {
      if (mounted) setState(() => error = 'Videoni yuklab bo‘lmadi.');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (error != null) {
      return _VideoFallback(url: widget.url, message: error!);
    }
    if (!requested) {
      return InkWell(
        onTap: _loadVideo,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 200,
          decoration: BoxDecoration(color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(20)),
          child: const Center(child: Column(mainAxisSize: MainAxisSize.min,
            children: [Icon(Icons.play_circle_fill_rounded, size: 58),
              SizedBox(height: 8), Text('Videoni ilovada o‘ynatish')])),
        ),
      );
    }
    final c = controller;
    if (!ready || c == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(20)),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final ratio = c.value.aspectRatio <= 0 ? 16 / 9 : c.value.aspectRatio;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, videoValue, _) => ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _toggle,
              child: AspectRatio(
                aspectRatio: ratio,
                child: Stack(alignment: Alignment.center, children: [
                  VideoPlayer(c),
                  if (!videoValue.isPlaying)
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                    ),
                ]),
              ),
            ),
            Row(children: [
              IconButton(onPressed: _toggle, icon: Icon(videoValue.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white)),
              Expanded(child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 8))),
              IconButton(onPressed: () => _openExternal(context, widget.url), icon: const Icon(Icons.open_in_new_rounded, color: Colors.white)),
            ]),
          ],
        ),
      ),
    ));
  }

  void _toggle() {
    final c = controller;
    if (c == null || !ready) { _loadVideo(); return; }
    if (c.value.isPlaying) { c.pause(); } else { c.play(); }
  }
}

class _VideoFallback extends StatelessWidget {
  const _VideoFallback({required this.url, required this.message});
  final String url;
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.play_circle_fill_rounded, size: 58),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(onPressed: () => _openExternal(context, url), icon: const Icon(Icons.open_in_new_rounded), label: const LocalizedText('Tashqi playerda ochish')),
        ]),
      ),
    );
  }
}

Future<void> _openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: LocalizedText('Faylni ochib bo‘lmadi.')));
  }
}
