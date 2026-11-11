import 'dart:typed_data';
import 'picked_video_preview.dart';
import 'ticket_text.dart';
import 'ticket_profile_editor.dart';
import '../../core/widgets/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/section_card.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

class TicketCreatePage extends StatefulWidget {
  const TicketCreatePage({super.key, required this.appState});

  final AppState appState;

  @override
  State<TicketCreatePage> createState() => _TicketCreatePageState();
}

class _TicketCreatePageState extends State<TicketCreatePage> {
  final picker = ImagePicker();
  final String _requestId = AppState.newRequestId();
  bool _picking = false;
  final descriptionController = TextEditingController();
  final attachments = <PickedAttachment>[];

  bool _submitting = false;

  @override
  void dispose() {

    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.appState.currentProfile;
    final colors = Theme.of(context).colorScheme;

    return PopScope(canPop: !_submitting && !_picking, child: Scaffold(
      appBar: AppBar(
        title: Text(widget.appState.tr('create_ticket_title')),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _CreateHeader(appState: widget.appState),
            const SizedBox(height: 14),
            SectionCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.person_outline_rounded), const SizedBox(width: 10),
                Expanded(child: Text(ticketText(context, 'contact'), style: Theme.of(context).textTheme.titleMedium)),
                IconButton(onPressed: _submitting || widget.appState.isTicketRequestCommitted(_requestId) ? null : () async {
                  await editTicketProfile(context, widget.appState);
                  if (mounted) setState(() {});
                }, icon: const Icon(Icons.edit_outlined)),
              ]),
              Text(profile?.fullName ?? ''),
              Text(profile?.phone ?? ''),
              Text(profile?.homeAddress.isNotEmpty == true ? profile!.homeAddress : ticketText(context, 'profile_required')),
              const SizedBox(height: 8),
              Text(ticketText(context, 'automatic'), style: Theme.of(context).textTheme.bodySmall),
            ])),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldTitle(
                    icon: Icons.description_rounded,
                    title: widget.appState.tr('problem_description'),
                    subtitle: widget.appState.tr('problem_description_subtitle'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: descriptionController,
                    enabled: !_submitting && !_picking && !widget.appState.isTicketRequestCommitted(_requestId),
                    maxLines: 5,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.description_rounded),
                      labelText: '${widget.appState.tr('problem_description')} *',
                      hintText: LocalizedText.translate(context, 'Masalan: 3-qavatda suv oqyapti...'),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _AttachmentBox(
              appState: widget.appState,
              attachments: attachments,
              enabled: !_submitting && !_picking,
              onAddImage: _pickImage,
              onAddVideo: _pickVideo,
              onRemove: (index) => setState(() => attachments.removeAt(index)),
            ),
            ValueListenableBuilder<double?>(valueListenable:widget.appState.uploadProgress,
              builder:(context,value,_)=>value==null?const SizedBox.shrink():Padding(
                padding:const EdgeInsets.only(top:12),child:LinearProgressIndicator(value:value))),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .18),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _submitting || _picking ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                  label: Text(_submitting ? widget.appState.tr('sending') : widget.appState.tr('submit_ticket')),
                ),
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> _pickImage() async => _pickMedia(false);
  Future<void> _pickVideo() async => _pickMedia(true);
  Future<void> _pickMedia(bool video) async {
    if (_submitting || _picking) return;
    if (attachments.length >= 6) { _message(ticketText(context, 'media_limit')); return; }
    setState(() => _picking = true);
    try {
      final file = video
          ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 60))
          : await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1800, maxHeight: 1800);
      if (file == null || !mounted) return;
      // Check before loading the complete file into memory.
      final length = await file.length();
      final limit = (video ? 60 : 8) * 1024 * 1024;
      if (length <= 0 || length > limit ||
          attachments.fold<double>(0, (sum, f) => sum + f.sizeInMb*1024*1024) + length > 120 * 1024 * 1024) {
        if (mounted) _message(ticketText(context, 'media_limit')); return;
      }
      final bytes = video && !kIsWeb ? Uint8List(0) : await file.readAsBytes();
      if (!mounted || (!video && bytes.isEmpty)) return;
      setState(() => attachments.add(PickedAttachment(name: file.name, bytes: bytes, isVideo: video, localPath: kIsWeb ? null : file.path,byteLength:length)));
    } catch (_) {
      if (mounted) _message(ticketText(context, 'media_error'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _picking) return;
    final profile = widget.appState.currentProfile;
    final description = descriptionController.text.trim();
    if (profile == null || [profile.firstName, profile.lastName, profile.phone,
        profile.neighborhood, profile.street, profile.houseNumber].any((s) => s.trim().isEmpty)) {
      _message(ticketText(context, 'profile_required'));
      await editTicketProfile(context, widget.appState);
      if (mounted) setState(() {});
      return;
    }
    if (description.isEmpty) { _message(widget.appState.tr('fill_ticket_required')); return; }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final created = await widget.appState.createTicket(
        addressText: profile.homeAddress,
        apartmentNumber: '',
        requestId: _requestId,
        description: description,
        attachments: List<PickedAttachment>.of(attachments),
      );
      if (!mounted) return;
      if (created) {

        descriptionController.clear();
        setState(() => attachments.clear());

        if (!mounted) return;
        _message(widget.appState.tr('ticket_created'));
        setState(() => _submitting = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        });
        widget.appState.setSelectedIndex(1);
      } else {
        _message(widget.appState.errorMessage ?? widget.appState.tr('ticket_create_failed'));
      }
    } catch (e) {
      if (!mounted) return;
      _message('Ariza yaratishda xato: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _CreateHeader extends StatelessWidget {
  const _CreateHeader({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.primaryContainer.withValues(alpha: .72), colors.surfaceContainerHighest],
        ),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
        boxShadow: [BoxShadow(color: colors.shadow.withValues(alpha: .06), blurRadius: 22, offset: const Offset(0, 12))],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: colors.surface.withValues(alpha: .62), borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.add_task_rounded, color: colors.primary, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText('Ariza yaratish', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  appState.tr('media_subtitle'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldTitle extends StatelessWidget {
  const _FieldTitle({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttachmentBox extends StatelessWidget {
  const _AttachmentBox({
    required this.appState, required this.attachments, required this.enabled, required this.onAddImage, required this.onAddVideo, required this.onRemove});
  final AppState appState;
  final List<PickedAttachment> attachments;
  final bool enabled;
  final VoidCallback onAddImage;
  final VoidCallback onAddVideo;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldTitle(icon: Icons.attach_file_rounded, title: appState.tr('image_video'), subtitle: appState.tr('media_subtitle')),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: .58),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.outlineVariant.withValues(alpha: .7)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: enabled ? onAddImage : null, icon: const Icon(Icons.image_rounded), label: Text(appState.tr('image')))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(onPressed: enabled ? onAddVideo : null, icon: const Icon(Icons.videocam_rounded), label: Text(appState.tr('video')))),
                  ],
                ),
                const SizedBox(height: 8),
                Text(ticketText(context, 'media_limit'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 14),
            _PickedPreviewGrid(attachments: attachments, enabled: enabled, onRemove: onRemove),
          ],
        ],
      ),
    );
  }
}

class _PickedPreviewGrid extends StatelessWidget {
  const _PickedPreviewGrid({required this.attachments, required this.enabled, required this.onRemove});
  final List<PickedAttachment> attachments;
  final bool enabled;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < attachments.length; i++)
          _PickedPreviewTile(attachment: attachments[i], index: i, enabled: enabled, onRemove: onRemove),
      ],
    );
  }
}

class _PickedPreviewTile extends StatelessWidget {
  const _PickedPreviewTile({required this.attachment, required this.index, required this.enabled, required this.onRemove});
  final PickedAttachment attachment;
  final int index;
  final bool enabled;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _showPreview(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 148,
                    height: 112,
                    color: colors.surfaceContainerHighest,
                    child: attachment.isVideo
                        ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [Icon(Icons.play_circle_fill_rounded, size: 40, color: colors.primary), const SizedBox(height: 6), const LocalizedText('Video')],
                    )
                        : Image.memory(attachment.bytes, fit: BoxFit.cover, cacheWidth: 320, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded)),
                  ),
                ),
              ),
              if (enabled)
                Positioned(
                  top: 6,
                  right: 6,
                  child: InkWell(
                    onTap: () => onRemove(index),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: colors.error, shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, size: 16, color: colors.onError),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text('${attachment.sizeInMb.toStringAsFixed(1)} MB', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  void _showPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Icon(attachment.isVideo ? Icons.videocam_rounded : Icons.image_rounded),
                    const SizedBox(width: 8),
                    Expanded(child: Text(attachment.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              Flexible(
                child: attachment.isVideo && attachment.localPath != null
                    ? PickedVideoPreview(path: attachment.localPath!)
                    : attachment.isVideo ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_fill_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 12),
                      const LocalizedText('Video tanlandi. Yuborilgandan keyin ariza ichida video sifatida ochiladi.', textAlign: TextAlign.center),
                    ],
                  ),
                )
                    : InteractiveViewer(child: Image.memory(attachment.bytes, fit: BoxFit.contain)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
