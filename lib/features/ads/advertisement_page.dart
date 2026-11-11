import 'dart:typed_data';
import '../../core/widgets/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/profile_avatar.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/media_viewer.dart';
import '../tickets/picked_video_preview.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

class AdvertisementPage extends StatefulWidget {
  const AdvertisementPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<AdvertisementPage> createState() => _AdvertisementPageState();
}

class _AdvertisementPageState extends State<AdvertisementPage> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  final urlController = TextEditingController();
  final linkLabelController = TextEditingController(text: 'Batafsil');
  final attachments = <PickedAttachment>[];
  String targetMode = 'all';
  String? selectedCompanyId;
  String? selectedProfileId;

  bool get isSuper => widget.appState.currentProfile?.role == UserRole.superAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.appState.refreshNotifications());
  }

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    urlController.dispose();
    linkLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.appState.currentProfile!;
    final companies = widget.appState.visibleCompanies();
    final users = widget.appState.visibleProfiles();
    final availableUsers = isSuper
        ? users.where((p) => p.id != me.id).toList()
        : users.where((p) => p.companyId == me.companyId && p.role == UserRole.user).toList();
    final sentAds = widget.appState.advertisementThreads(sentOnly: true);
    final receivedAds = widget.appState.advertisementThreads(receivedOnly: true);

    return RefreshIndicator(
      onRefresh: () => widget.appState.refreshNotifications(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.campaign_rounded, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.appState.tr('ads_center'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      tooltip: widget.appState.tr('refresh'),
                      onPressed: () async {
                        await widget.appState.refreshNotifications();
                        if (mounted) _message(widget.appState.tr('ads_refreshed'));
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isSuper
                      ? 'Super Admin hammaga, tanlangan tashkilotga yoki bitta userga matn + rasm/GIF/video yuboradi. User bo‘lmasa ham reklama public saqlanadi va keyin kirganlar ko‘radi.'
                      : 'Direktor/Admin o‘z tashkilotiga public reklama yuboradi. Userlar keyin kirsa ham dashboardda ko‘radi. O‘zi yaratgan reklamani edit/delete qiladi.',
                ),
              ],
            ),
          ),
          if (isSuper)
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText('Kimga yuboriladi?', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  RadioGroup<String>(
                    groupValue: targetMode,
                    onChanged: (value) {
                      if (value != null) setState(() => targetMode = value);
                    },
                    child: Column(children: [
                  RadioListTile<String>(
                    value: 'all',
                    title: const LocalizedText('Hammaga'),
                    subtitle: const LocalizedText('Barcha tashkilot va userlarga'),
                  ),
                  RadioListTile<String>(
                    value: 'company',
                    title: const LocalizedText('Tanlangan tashkilotga'),
                  ),
                  if (targetMode == 'company')
                    DropdownButtonFormField<String>(
                      initialValue: selectedCompanyId,
                      decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'Tashkilot'), prefixIcon: Icon(Icons.apartment_rounded)),
                      items: companies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                      onChanged: (v) => setState(() => selectedCompanyId = v),
                    ),
                  RadioListTile<String>(
                    value: 'user',
                    title: const LocalizedText('Bitta userga'),
                  ),
                    ]),
                  ),
                  if (targetMode == 'user')
                    DropdownButtonFormField<String>(
                      initialValue: selectedProfileId,
                      decoration:  InputDecoration(labelText: LocalizedText.translate(context, 'User'), prefixIcon: Icon(Icons.person_rounded)),
                      items: availableUsers
                          .map((p) => DropdownMenuItem(value: p.id, child: Text('${p.fullName} • ${widget.appState.tr(p.role.dbValue)}')))
                          .toList(),
                      onChanged: (v) => setState(() => selectedProfileId = v),
                    ),
                ],
              ),
            )
          else
            SectionCard(
              child: ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: const LocalizedText('O‘z tashkilotidagi userlarga'),
                subtitle: Text('Public reklama sifatida saqlanadi. Hozir ${availableUsers.length} ta user bor, keyin kirganlar ham ko‘radi.'),
              ),
            ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.appState.tr('new_ad'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: widget.appState.tr('title'), prefixIcon: const Icon(Icons.campaign_rounded)),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  onChanged: (_) => setState(() {}),
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: widget.appState.tr('text'), prefixIcon: const Icon(Icons.notes_rounded)),
                ),
                const SizedBox(height: 14),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [Icon(Icons.link_rounded), SizedBox(width: 8), Expanded(child: Text('Havola va harakat tugmasi (ixtiyoriy)', style: TextStyle(fontWeight: FontWeight.w700)))]),
                        const SizedBox(height: 10),
                        TextField(
                          controller: urlController,
                          keyboardType: TextInputType.url,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Havola',
                            hintText: 'https://example.uz/aksiya',
                            prefixIcon: Icon(Icons.public_rounded),
                            helperText: 'Qabul qiluvchi tugmani bossa ushbu sayt ochiladi.',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: linkLabelController,
                          onChanged: (_) => setState(() {}),
                          maxLength: 40,
                          decoration: const InputDecoration(labelText: 'Tugma yozuvi', prefixIcon: Icon(Icons.smart_button_rounded), hintText: 'Batafsil'),
                        ),
                        if (urlController.text.trim().isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ActionChip(
                              avatar: const Icon(Icons.open_in_new_rounded, size: 18),
                              label: Text('Ko‘rinishi: ${linkLabelController.text.trim().isEmpty ? 'Batafsil' : linkLabelController.text.trim()}'),
                              onPressed: () => openAdvertisementLink(context, urlController.text),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(onPressed: _pickImageOrGif, icon: const Icon(Icons.image_rounded), label: Text(widget.appState.tr('image_gif'))),
                    OutlinedButton.icon(onPressed: _pickVideo, icon: const Icon(Icons.videocam_rounded), label: Text(widget.appState.tr('video'))),
                    if (attachments.isNotEmpty)
                      OutlinedButton.icon(onPressed: () => setState(attachments.clear), icon: const Icon(Icons.cleaning_services_rounded), label: Text(widget.appState.tr('clear_media'))),
                  ],
                ),
                _AttachmentList(attachments: attachments, onRemove: (i) => setState(() => attachments.removeAt(i))),
                if (titleController.text.trim().isNotEmpty || bodyController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Reklama ko‘rinishi', style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.campaign_rounded, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(titleController.text.trim().isEmpty
                            ? 'Reklama sarlavhasi' : titleController.text.trim(),
                            style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800))),
                        ]),
                        const SizedBox(height: 9),
                        Text(bodyController.text.trim().isEmpty
                          ? 'Reklama matni shu yerda ko‘rinadi.' : bodyController.text.trim(),
                          maxLines: 5, overflow: TextOverflow.ellipsis),
                        if (attachments.isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 8),
                            child: Text('Biriktirilgan media: ${attachments.length} ta')),
                        if (urlController.text.trim().isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 10),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.open_in_new_rounded, size: 17),
                              const SizedBox(width: 6),
                              Flexible(child: Text(linkLabelController.text.trim().isEmpty
                                ? 'Batafsil' : linkLabelController.text.trim(),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ])),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: widget.appState.loading ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(widget.appState.loading ? widget.appState.tr('sending') : widget.appState.tr('send_ad')),
                ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.appState.tr('sent_ads'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (sentAds.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(widget.appState.tr('no_sent_ads')))
                else
                  ...sentAds.map((ad) => _AdvertisementCard(
                        appState: widget.appState,
                        ad: ad,
                        sent: true,
                        onEdit: () => _edit(ad),
                        onDelete: () => _delete(ad),
                      )),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.appState.tr('received_ads'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                if (receivedAds.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(widget.appState.tr('no_received_ads')))
                else
                  ...receivedAds.map((ad) => _AdvertisementCard(appState: widget.appState, ad: ad)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImageOrGif() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
      if (file == null) return;
      final length = await file.length();
      if (length > 10 * 1024 * 1024) {
        if (mounted) _message('Rasm/GIF maksimal 10 MB bo‘lsin.');
        return;
      }
      final picked = PickedAttachment(name: file.name, bytes: await file.readAsBytes(), isVideo: false);
      if (picked.sizeInMb > 10) {
        _message('Rasm/GIF maksimal 10 MB bo‘lsin.');
        return;
      }
      if (mounted) setState(() => attachments.add(picked));
    } catch (e) {
      _message('Media tanlashda xato: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
      if (file == null) return;
      final length = await file.length();
      if (length <= 0) throw const FormatException('Video fayl bo‘sh.');
      final picked = PickedAttachment(name: file.name,
        bytes: kIsWeb ? await file.readAsBytes() : Uint8List(0),
        isVideo: true, localPath: kIsWeb ? null : file.path, byteLength: length);
      if (picked.sizeInMb > 80) {
        _message('Video maksimal 80 MB bo‘lsin.');
        return;
      }
      if (mounted) setState(() => attachments.add(picked));
    } catch (e) {
      _message('Video tanlashda xato: $e');
    }
  }

  Future<void> _send() async {
    if (isSuper && ((targetMode == 'company' && selectedCompanyId == null) ||
        (targetMode == 'user' && selectedProfileId == null))) {
      _message('Reklama yuborish uchun qabul qiluvchini tanlang.');
      return;
    }
    final ok = await widget.appState.sendAdvertisement(
      title: titleController.text,
      body: bodyController.text,
      actionUrl: urlController.text,
      actionLabel: linkLabelController.text,
      targetMode: isSuper ? targetMode : 'own_company_users',
      targetCompanyId: selectedCompanyId,
      targetProfileId: selectedProfileId,
      attachments: attachments,
    );
    if (!mounted) return;
    if (ok) {
      titleController.clear();
      bodyController.clear();
      urlController.clear();
      linkLabelController.text = 'Batafsil';
      setState(() => attachments.clear());
      _message('Reklama yuborildi va ro‘yxatda ko‘rinadi.');
    } else {
      _message(widget.appState.errorMessage ?? 'Reklama yuborilmadi.');
    }
  }

  Future<void> _edit(ServiceNotification ad) async {
    final title = TextEditingController(text: ad.title);
    final body = TextEditingController(text: ad.body);
    final actionUrl = TextEditingController(text: ad.actionUrl ?? '');
    final actionLabel = TextEditingController(text: ad.actionLabel);
    final newFiles = <PickedAttachment>[];
    var replaceMedia = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const LocalizedText('Reklamani tahrirlash'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: title, decoration: InputDecoration(labelText: widget.appState.tr('title'))),
                  const SizedBox(height: 10),
                  TextField(controller: body, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: widget.appState.tr('text'))),
                  const SizedBox(height: 10),
                  TextField(controller: actionUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Havola (ixtiyoriy)', hintText: 'https://example.uz', prefixIcon: Icon(Icons.link_rounded))),
                  const SizedBox(height: 10),
                  TextField(controller: actionLabel, maxLength: 40, decoration: const InputDecoration(labelText: 'Havola tugmasining nomi')),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: replaceMedia,
                    onChanged: (v) => setDialogState(() => replaceMedia = v ?? false),
                    title: const LocalizedText('Eski medialarni almashtirish'),
                    subtitle: const LocalizedText('Belgilanmasa yangi media eskisiga qo‘shiladi'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
                          if (file == null) return;
                          final length = await file.length();
                          if (length <= 0 || length > 10 * 1024 * 1024) return;
                          final picked = PickedAttachment(name: file.name, bytes: await file.readAsBytes(), isVideo: false);
                          if (!context.mounted) return;
                          setDialogState(() => newFiles.add(picked));
                        },
                        icon: const Icon(Icons.image_rounded),
                        label: Text(widget.appState.tr('image_gif')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final file = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 2));
                          if (file == null) return;
                          final length = await file.length();
                          if (length <= 0 || length > 80 * 1024 * 1024) return;
                          final picked = PickedAttachment(name: file.name,
                            bytes: kIsWeb ? await file.readAsBytes() : Uint8List(0),
                            isVideo: true, localPath: kIsWeb ? null : file.path, byteLength: length);
                          if (!context.mounted) return;
                          setDialogState(() => newFiles.add(picked));
                        },
                        icon: const Icon(Icons.videocam_rounded),
                        label: Text(widget.appState.tr('video')),
                      ),
                    ],
                  ),
                  _AttachmentList(attachments: newFiles, onRemove: (i) => setDialogState(() => newFiles.removeAt(i))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('Bekor')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('Saqlash')),
          ],
        ),
      ),
    );
    if (result != true) {
      title.dispose();
      body.dispose();
      actionUrl.dispose();
      actionLabel.dispose();
      return;
    }
    final ok = await widget.appState.editAdvertisement(
      advertisement: ad,
      title: title.text,
      body: body.text,
      actionUrl: actionUrl.text,
      actionLabel: actionLabel.text,
      newAttachments: newFiles,
      replaceMedia: replaceMedia,
    );
    title.dispose();
    body.dispose();
    actionUrl.dispose();
    actionLabel.dispose();
    if (!mounted) return;
    _message(ok ? 'Reklama yangilandi.' : (widget.appState.errorMessage ?? 'Reklama yangilanmadi.'));
  }

  Future<void> _delete(ServiceNotification ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LocalizedText('Reklamani o‘chirish'),
        content: const LocalizedText('Bu reklama barcha qabul qiluvchilar ro‘yxatidan o‘chadi. Davom etasizmi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const LocalizedText('Yo‘q')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const LocalizedText('Ha, o‘chirish')),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await widget.appState.deleteAdvertisement(ad);
    if (!mounted) return;
    _message(deleted ? 'Reklama o‘chirildi.' : (widget.appState.errorMessage ?? 'O‘chirilmadi.'));
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _AdvertisementCard extends StatelessWidget {
  const _AdvertisementCard({required this.appState, required this.ad, this.sent = false, this.onEdit, this.onDelete});

  final AppState appState;
  final ServiceNotification ad;
  final bool sent;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final sender = ad.sentBy == null ? null : appState.profileById(ad.sentBy!);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => MediaViewerDialog(
            title: ad.title,
            body: ad.body,
            mediaUrls: ad.mediaUrls,
            mediaTypes: ad.mediaTypes,
            actionUrl: ad.actionUrl,
            actionLabel: ad.actionLabel,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(profile: sender, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ad.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(sent ? 'Men yuborganman' : 'Yubordi: ${sender?.fullName ?? 'Tizim'}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (onEdit != null) IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
                if (onDelete != null) IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            Text(ad.body),
            if (ad.actionUrl != null && ad.actionUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => openAdvertisementLink(context, ad.actionUrl!),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(ad.actionLabel.trim().isEmpty ? 'Batafsil' : ad.actionLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
            if (ad.mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < ad.mediaUrls.length; i++)
                    ActionChip(
                      avatar: Icon((i < ad.mediaTypes.length && ad.mediaTypes[i] == 'video') ? Icons.play_circle_rounded : Icons.image_rounded),
                      label: Text(i < ad.mediaTypes.length && ad.mediaTypes[i] == 'video' ? 'Video' : (i < ad.mediaTypes.length && ad.mediaTypes[i] == 'gif' ? 'GIF' : 'Rasm')),
                      onPressed: () => _showMedia(context, ad.mediaUrls[i]),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => MediaViewerDialog(
                    title: ad.title,
                    body: ad.body,
                    mediaUrls: ad.mediaUrls,
                    mediaTypes: ad.mediaTypes,
                    actionUrl: ad.actionUrl,
                    actionLabel: ad.actionLabel,
                  ),
                ),
                icon: const Icon(Icons.open_in_full_rounded),
                label: const LocalizedText('Kengroq ko‘rish'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _showMedia(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) => MediaViewerDialog(
        title: ad.title,
        body: ad.body,
        mediaUrls: [url],
        mediaTypes: [
          ad.mediaUrls.indexOf(url) < ad.mediaTypes.length ? ad.mediaTypes[ad.mediaUrls.indexOf(url)] : '',
        ],
        actionUrl: ad.actionUrl,
        actionLabel: ad.actionLabel,
      ),
    );
  }
}

class _AttachmentList extends StatelessWidget {
  const _AttachmentList({required this.attachments, required this.onRemove});

  final List<PickedAttachment> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      children: attachments.asMap().entries.map((entry) {
        final file = entry.value;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          onTap: file.isVideo && file.localPath != null
            ? () => showDialog<void>(context: context,
                builder: (_) => Dialog(child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: PickedVideoPreview(path: file.localPath!))))
            : !file.isVideo && file.bytes.isNotEmpty
              ? () => showDialog<void>(context: context,
                  builder: (_) => Dialog(child: InteractiveViewer(
                    child: Image.memory(file.bytes, fit: BoxFit.contain))))
              : null,
          leading: Icon(file.isVideo ? Icons.videocam_rounded : Icons.image_rounded),
          title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${file.sizeInMb.toStringAsFixed(1)} MB'),
          trailing: IconButton(onPressed: () => onRemove(entry.key), icon: const Icon(Icons.close_rounded)),
        );
      }).toList(),
    );
  }
}
