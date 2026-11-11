import 'picked_video_preview.dart';
import 'dart:typed_data';
import 'worker_actions.dart';
import '../workflow/workflow_text.dart';
import '../../core/widgets/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../../core/widgets/media_viewer.dart';

import '../../core/widgets/app_route.dart';
import '../../core/widgets/section_card.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'ticket_create_page.dart';

Future<void> showTicketDetails(BuildContext context, AppState appState, Ticket ticket) =>
  showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width >= 980 ? 860 : double.infinity),
    builder:(_)=>_TicketDetailsSheet(appState:appState,ticket:ticket));

class TicketsPage extends StatelessWidget {
  const TicketsPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final tickets = appState.visibleTickets();

    // HomeShell uses extendBody on phones: the transparent navigation bar is
    // painted on top of this inner Scaffold. Keep its action clear of the bar.
    final navigationInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: navigationInset),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).push(
            smoothRoute<void>(TicketCreatePage(appState: appState)),
          ),
          icon: const Icon(Icons.add_rounded),
          label: Text(appState.tr('create_ticket')),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await appState.refreshTickets();
          await appState.refreshNotifications();
        },
        child: tickets.isEmpty
            ? ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 120),
            EmptyState(
              icon: Icons.assignment_outlined,
              title: appState.tr('tickets_empty'),
              subtitle: appState.tr('tickets_empty_subtitle'),
            ),
          ],
        )
            : ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + navigationInset),
          itemCount: tickets.length,
          itemBuilder: (context, index) => _TicketCard(appState: appState, ticket: tickets[index]),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.appState, required this.ticket});

  final AppState appState;
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final building = appState.buildingById(ticket.buildingId);
    final author = appState.profileById(ticket.createdBy);
    final profile = appState.currentProfile!;
    final canManage = profile.role == UserRole.admin || profile.role == UserRole.director || profile.role == UserRole.superAdmin || profile.role == UserRole.worker;
    final requester = _requesterInfo(author, ticket);
    final hasMedia = ticket.attachments.isNotEmpty;

    return SectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: ticket.status.color(colors).withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_statusIcon(ticket.status), color: ticket.status.color(colors)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ticket.number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Chip(
                    label: Text(appState.tr('ticket_${ticket.status.dbValue}')),
                    backgroundColor: ticket.status.color(colors).withValues(alpha: 0.14),
                    side: BorderSide(color: ticket.status.color(colors).withValues(alpha: 0.3)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Info(icon: Icons.location_on_rounded, text: ticket.apartmentNumber.isEmpty ? ticket.addressLabel(building) : '${ticket.addressLabel(building)}, ${ticket.apartmentNumber}-xonadon'),
              _Info(icon: Icons.person_rounded, text: requester.name),
              _Info(icon: Icons.call_rounded, text: requester.phoneLabel),
              const SizedBox(height: 10),
              Text(ticket.description, maxLines: 3, overflow: TextOverflow.ellipsis),
              if (hasMedia) ...[
                const SizedBox(height: 10),
                _SmallMediaLine(appState: appState, count: ticket.attachments.length),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(onPressed: () => _openDetails(context), icon: const Icon(Icons.visibility_rounded), label: Text(appState.tr('view_full'))),
                  if (canManage && ticket.status == TicketStatus.newTicket)
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final worker=await chooseTicketWorker(context,appState,ticket);
                        if(worker==null || !context.mounted)return;
                        await appState.acceptTicket(ticket,workerId:worker);
                        if(context.mounted && appState.errorMessage!=null)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(appState.errorMessage!)));
                        await appState.refreshTickets();
                        await appState.refreshNotifications();
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(appState.tr('accept')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(TicketStatus status) {
    switch (status) {
      case TicketStatus.newTicket:
        return Icons.fiber_new_rounded;
      case TicketStatus.inProgress:
        return Icons.pending_actions_rounded;
      case TicketStatus.completed:
        return Icons.verified_rounded;
      case TicketStatus.closed:
        return Icons.done_all_rounded;
    }
  }

  void _openDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width >= 980 ? 860 : double.infinity),
      builder: (_) => _TicketDetailsSheet(appState: appState, ticket: ticket),
    );
  }
}

class _SmallMediaLine extends StatelessWidget {
  const _SmallMediaLine({required this.appState, required this.count});
  final AppState appState;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: .72), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file_rounded, size: 17, color: colors.primary),
          const SizedBox(width: 5),
          Text('$count ${appState.tr('media_count')}', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _TicketDetailsSheet extends StatefulWidget {
  const _TicketDetailsSheet({required this.appState, required this.ticket});
  final AppState appState;
  final Ticket ticket;

  @override
  State<_TicketDetailsSheet> createState() => _TicketDetailsSheetState();
}

class _TicketDetailsSheetState extends State<_TicketDetailsSheet> {
  bool _actionLoading = false;
  Map<String,dynamic>? _review;
  @override void initState(){super.initState();_loadReview();}
  Future<void> _loadReview() async {
    try {
      final row=await widget.appState.client.from('worker_ratings').select('score,comment').eq('ticket_id',widget.ticket.id).maybeSingle();
      if(mounted)setState(()=>_review=row);
    } catch(_) {}
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    final ticket = _latestTicket;
    final building = appState.buildingById(ticket.buildingId);
    final author = appState.profileById(ticket.createdBy);
    final accepter = ticket.acceptedBy == null ? null : appState.profileById(ticket.acceptedBy!);
    final completer = ticket.completedBy == null ? null : appState.profileById(ticket.completedBy!);
    final profile = appState.currentProfile!;
    final canManage = profile.role == UserRole.admin || profile.role == UserRole.director || profile.role == UserRole.superAdmin || profile.role == UserRole.worker;
    final requester = _requesterInfo(author, ticket);
    final colors = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.96,
      minChildSize: 0.45,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: ticket.status.color(colors).withValues(alpha: .13), borderRadius: BorderRadius.circular(18)),
                  child: Icon(Icons.assignment_rounded, color: ticket.status.color(colors)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(ticket.number, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                ),
                Chip(label: Text(appState.tr('ticket_${ticket.status.dbValue}'))),
              ],
            ),
            const SizedBox(height: 16),
            _DetailsBlock(
              children: [
                _DetailRow(label: appState.tr('address'), value: ticket.apartmentNumber.isEmpty ? ticket.addressLabel(building) : '${ticket.addressLabel(building)}, ${ticket.apartmentNumber}-xonadon'),
                _DetailRow(label: appState.tr('requester'), value: requester.name),
                _DetailRow(label: appState.tr('phone'), value: requester.phoneLabel),
                _DetailRow(label: appState.tr('created_at'), value: _date(ticket.createdAt.toLocal())),
                if (accepter != null) _DetailRow(label: appState.tr('accepted_by'), value: accepter.fullName),
                if (completer != null) _DetailRow(label: workflowText(context,'worker'), value: completer.fullName),
                if(ticket.acceptedAt!=null)_DetailRow(label:workflowText(context,'accepted_at'),value:_date(ticket.acceptedAt!.toLocal())),
                if(ticket.completedAt!=null)_DetailRow(label:workflowText(context,'done_at'),value:_date(ticket.completedAt!.toLocal())),
              ],
            ),
            const SizedBox(height: 14),
            _DescriptionBlock(title: appState.tr('problem_description'), text: ticket.description),
            if(_review!=null) Padding(padding:const EdgeInsets.only(top:12),child:_DescriptionBlock(title:'${workflowText(context,'review')} • ${_review!['score']} / 5',text:'${_review!['comment']??''}')),
            _UrlAttachments(title: appState.tr('request_media'), urls: ticket.attachments),
            if (ticket.completionDescription != null) ...[
              const SizedBox(height: 14),
              _DescriptionBlock(title: appState.tr('completion_desc'), text: ticket.completionDescription!),
              _UrlAttachments(title: appState.tr('completion_media'), urls: ticket.completionAttachments),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (canManage && ticket.status == TicketStatus.newTicket)
                  FilledButton.tonalIcon(
                    onPressed: _actionLoading ? null : _acceptTicket,
                    icon: _actionLoading ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
                    label: Text(_actionLoading ? 'Yuborilmoqda...' : 'Qabul qilish'),
                  ),
                if (canManage && ticket.status == TicketStatus.inProgress && (profile.role != UserRole.worker || ticket.acceptedBy == profile.id))
                  FilledButton.icon(onPressed: _actionLoading ? null : () => _showCompleteDialog(context), icon: const Icon(Icons.check_circle_rounded), label: Text(appState.tr('complete'))),
                if (profile.role==UserRole.user && profile.id == ticket.createdBy && ticket.completedBy != null &&
                    (ticket.status == TicketStatus.completed || ticket.status == TicketStatus.closed))
                  OutlinedButton.icon(onPressed: _actionLoading || _review!=null ? null : _rateWork,
                    icon: const Icon(Icons.star_outline), label: Text(appState.tr('rate_work'))),
                if (profile.role == UserRole.user && ticket.status == TicketStatus.completed)
                  FilledButton.tonalIcon(
                    onPressed: _actionLoading ? null : _closeTicket,
                    icon: _actionLoading ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.done_all_rounded),
                    label: Text(_actionLoading ? 'Yuborilmoqda...' : 'Yopish'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Ticket get _latestTicket {
    for (final item in widget.appState.visibleTickets()) {
      if (item.id == widget.ticket.id) return item;
    }
    return widget.ticket;
  }

  Future<void> _rateWork() async {
    final state = widget.appState;
    final review=await showWorkerReview(context,state);
    if(review==null || !mounted)return;
    setState(()=>_actionLoading=true);
    final ok=await state.rateWorker(_latestTicket,review.score,review.comment);
    if(mounted){
      if(ok)await _loadReview();
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(state.tr(ok?'rating_saved':'rating_failed'))));
      setState(()=>_actionLoading=false);
    }
  }

  Future<void> _acceptTicket() async {
    final worker=await chooseTicketWorker(context,widget.appState,_latestTicket);
    if(worker==null || !mounted)return;
    setState(() => _actionLoading = true);
    try {
      await widget.appState.acceptTicket(_latestTicket,workerId:worker);
      if(mounted && widget.appState.errorMessage!=null)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(widget.appState.errorMessage!)));
      await widget.appState.refreshTickets();
      await widget.appState.refreshNotifications();
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _closeTicket() async {
    setState(() => _actionLoading = true);
    try {
      await widget.appState.closeTicket(_latestTicket);
      await widget.appState.refreshTickets();
      await widget.appState.refreshNotifications();
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  void _showCompleteDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CompleteTicketDialog(
        appState: widget.appState,
        ticket: _latestTicket,
        onCompleted: () async {
          await widget.appState.refreshTickets();
          await widget.appState.refreshNotifications();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  String _date(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
  }
}

class _DetailsBlock extends StatelessWidget {
  const _DetailsBlock({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(20), border: Border.all(color: colors.outlineVariant.withValues(alpha: .7))),
      child: Column(children: children),
    );
  }
}

class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({required this.title, required this.text});
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: colors.outlineVariant.withValues(alpha: .7))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(text)]),
    );
  }
}

class _CompleteTicketDialog extends StatefulWidget {
  const _CompleteTicketDialog({required this.appState, required this.ticket, required this.onCompleted});
  final AppState appState;
  final Ticket ticket;
  final Future<void> Function() onCompleted;

  @override
  State<_CompleteTicketDialog> createState() => _CompleteTicketDialogState();
}

class _CompleteTicketDialogState extends State<_CompleteTicketDialog> {
  final picker = ImagePicker();
  final controller = TextEditingController();
  final files = <PickedAttachment>[];
  bool _submitting = false;
  bool _picking = false;
  String? _workerId;
  @override void initState(){
    super.initState();
    final me=widget.appState.currentProfile;
    final workers=widget.appState.workersForCompany(widget.ticket.companyId);
    _workerId=me?.role==UserRole.worker?me!.id:
      workers.any((p)=>p.id==widget.ticket.acceptedBy)?widget.ticket.acceptedBy:
      workers.isEmpty?null:workers.first.id;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(canPop: !_submitting && !_picking, child: AlertDialog(
      insetPadding: const EdgeInsets.all(18),
      title: Text(widget.appState.tr('complete_ticket_title')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if(widget.appState.currentProfile?.role!=UserRole.worker) ...[
                DropdownButtonFormField<String>(initialValue:_workerId,isExpanded:true,
                  decoration:InputDecoration(labelText:workflowText(context,'worker')),
                  items:widget.appState.workersForCompany(widget.ticket.companyId).map((p)=>DropdownMenuItem(value:p.id,child:Text(p.fullName))).toList(),
                  onChanged:_submitting?null:(value)=>setState(()=>_workerId=value)),
                const SizedBox(height:12),
              ],
              TextField(controller: controller, enabled: !_submitting, maxLines: 4, decoration: InputDecoration(labelText: '${widget.appState.tr('completion_desc')} *', alignLabelWithHint: true, border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: .62), borderRadius: BorderRadius.circular(18), border: Border.all(color: colors.outlineVariant.withValues(alpha: .7))),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(widget.appState.tr('required_completion_media'), style: const TextStyle(fontWeight: FontWeight.w800))),
                        IconButton.filledTonal(onPressed: _submitting || _picking ? null : _pickImage, icon: const Icon(Icons.image_rounded)),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(onPressed: _submitting || _picking ? null : _pickVideo, icon: const Icon(Icons.videocam_rounded)),
                      ],
                    ),
                    Wrap(spacing:8,children:[
                      TextButton.icon(onPressed:_submitting||_picking?null:()=>_pickMedia(false,ImageSource.camera),icon:const Icon(Icons.camera_alt_outlined),label:Text(workflowText(context,'camera'))),
                      TextButton.icon(onPressed:_submitting||_picking?null:()=>_pickMedia(true,ImageSource.camera),icon:const Icon(Icons.videocam_outlined),label:Text(workflowText(context,'video_camera'))),
                    ]),
                    if(_picking)const LinearProgressIndicator(),
                    ValueListenableBuilder<double?>(valueListenable:widget.appState.uploadProgress,builder:(context,value,_)=>value==null?const SizedBox.shrink():Column(children:[Text(workflowText(context,'progress')),LinearProgressIndicator(value:value)])),
                    Text(widget.appState.tr('media_limit'), style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (files.isNotEmpty) ...[
                const SizedBox(height: 12),
                _PickedFilesPreview(files: files, enabled: !_submitting, onRemove: (i) => setState(() => files.removeAt(i))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting || _picking ? null : () => Navigator.pop(context), child: Text(widget.appState.tr('cancel'))),
        FilledButton(onPressed: _submitting || _picking ? null : _submit, child: Text(_submitting ? widget.appState.tr('sending') : widget.appState.tr('send'))),
      ],
    ));
  }

  Future<void> _pickImage()=>_pickMedia(false,ImageSource.gallery);
  Future<void> _pickVideo()=>_pickMedia(true,ImageSource.gallery);
  Future<void> _pickMedia(bool video,ImageSource source) async {
    if(_picking || _submitting)return;
    if(files.length>=6)return _message(widget.appState.tr('media_limit'));
    setState(()=>_picking=true);
    try {
      final file=video?await picker.pickVideo(source:source,maxDuration:const Duration(seconds:60)):
        await picker.pickImage(source:source,imageQuality:78,maxWidth:1600,maxHeight:1600);
      if(file==null || !mounted)return;
      final length=await file.length();
      if(length<=0 || length>(video?60:8)*1024*1024 ||
          files.fold<double>(0,(sum,f)=>sum+f.sizeInMb)+length/(1024*1024)>120){
        if(mounted)_message(widget.appState.tr('media_limit'));return;
      }
      final bytes=video && !kIsWeb?Uint8List(0):await file.readAsBytes();
      if(!mounted)return;
      setState(()=>files.add(PickedAttachment(name:file.name,bytes:bytes,isVideo:video,localPath:kIsWeb ? null : file.path,byteLength:length)));
    } catch(_){if(mounted)_message(widget.appState.tr('media_failed'));}
    finally{if(mounted)setState(()=>_picking=false);}
  }

  Future<void> _submit() async {
    if(_submitting || _picking)return;
    if(_workerId==null)return _message(workflowText(context,'choose'));
    final description = controller.text.trim();
    if (description.isEmpty || files.isEmpty) return _message('${widget.appState.tr('completion_desc')} ${widget.appState.tr('required_completion_media')}');
    setState(() => _submitting = true);
    try {
      await widget.appState.completeTicket(ticket: widget.ticket, description: description, attachments: List<PickedAttachment>.of(files),workerId:_workerId);
      if (!mounted) return;
      if (widget.appState.errorMessage == null) {
        await widget.onCompleted();
        if (!mounted) return;
        setState(()=>_submitting=false);
        WidgetsBinding.instance.addPostFrameCallback((_){
          if(mounted && ModalRoute.of(context)?.isCurrent==true)Navigator.pop(context);
        });
      } else {
        _message(widget.appState.errorMessage ?? widget.appState.tr('ticket_create_failed'));
      }
    } catch (e) {
      if (!mounted) return;
      _message('Arizani yakunlashda xato: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _PickedFilesPreview extends StatelessWidget {
  const _PickedFilesPreview({required this.files, required this.enabled, required this.onRemove});
  final List<PickedAttachment> files;
  final bool enabled;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < files.length; i++) _PickedFileTile(file: files[i], index: i, enabled: enabled, onRemove: onRemove),
      ],
    );
  }
}

class _PickedFileTile extends StatelessWidget {
  const _PickedFileTile({required this.file, required this.index, required this.enabled, required this.onRemove});
  final PickedAttachment file;
  final int index;
  final bool enabled;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 132,
      child: Stack(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _preview(context),
            child: Container(
              width: 132,
              height: 106,
              decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.outlineVariant.withValues(alpha: .7))),
              clipBehavior: Clip.antiAlias,
              child: file.isVideo
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_circle_fill_rounded, size: 36, color: colors.primary), const SizedBox(height: 5), const LocalizedText('Video')])
                  : Image.memory(file.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded)),
            ),
          ),
          if (enabled)
            Positioned(
              right: 4,
              top: 4,
              child: InkWell(
                onTap: () => onRemove(index),
                child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: colors.error, shape: BoxShape.circle), child: Icon(Icons.close_rounded, color: colors.onError, size: 16)),
              ),
            ),
        ],
      ),
    );
  }

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.isVideo ? 'Video tanlandi' : 'Rasm tanlandi'),
        content: SizedBox(width:520,child:file.isVideo && file.localPath!=null ? PickedVideoPreview(path:file.localPath!) : file.isVideo ? const Icon(Icons.videocam_outlined) : InteractiveViewer(child: Image.memory(file.bytes))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const LocalizedText('Yopish'))],
      ),
    );
  }
}

class _UrlAttachments extends StatelessWidget {
  const _UrlAttachments({required this.title, required this.urls});
  final String title;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final validUrls = urls.where((url) => url.trim().isNotEmpty).toList();
    if (validUrls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: validUrls.map((url) => _UrlMediaTile(url: url)).toList()),
        ],
      ),
    );
  }
}

class _UrlMediaTile extends StatelessWidget {
  const _UrlMediaTile({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isVideo = _isVideo(url);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showUrl(context, url),
      child: Container(
        width: 160,
        decoration: BoxDecoration(color: colors.surfaceContainerHighest.withValues(alpha: .64), borderRadius: BorderRadius.circular(18), border: Border.all(color: colors.outlineVariant.withValues(alpha: .7))),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              width: 160,
              height: 112,
              child: isVideo
                  ? Container(color: colors.secondaryContainer, child: Center(child: Icon(Icons.play_circle_fill_rounded, size: 42, color: colors.onSecondaryContainer)))
                  : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 360,
                loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(isVideo ? Icons.videocam_rounded : Icons.image_rounded, size: 17, color: colors.primary),
                  const SizedBox(width: 5),
                  Expanded(child: Text(isVideo ? 'Video' : 'Rasm', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUrl(BuildContext context, String url) {
    final isVideo = _isVideo(url);
    showDialog<void>(
      context: context,
      builder: (_) => MediaViewerDialog(
        title: isVideo ? 'Video fayl' : 'Rasm fayl',
        body: '',
        mediaUrls: [url],
        mediaTypes: [isVideo ? 'video' : 'image'],
      ),
    );
  }

  bool _isVideo(String url) {
    final clean = url.toLowerCase().split('?').first;
    return clean.endsWith('.mp4') || clean.endsWith('.mov') || clean.endsWith('.webm') || clean.endsWith('.m4v');
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [SizedBox(width: 124, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))), Expanded(child: Text(value))],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 8), Expanded(child: Text(text))]),
    );
  }
}

_RequesterInfo _requesterInfo(Profile? profile, Ticket ticket) {
  final snapshot = ticket.requesterSnapshot;
  final name = '${snapshot['first_name'] ?? ''} ${snapshot['last_name'] ?? ''}'.trim();
  final phone = '${snapshot['phone'] ?? ''}'.trim();
  return _RequesterInfo(name: name.isNotEmpty ? name : (profile?.fullName ?? 'Noma’lum foydalanuvchi'),
    phoneLabel: phone.isNotEmpty ? phone : (profile?.phone ?? ''));
}

class _RequesterInfo {
  const _RequesterInfo({required this.name, required this.phoneLabel});
  final String name;
  final String phoneLabel;
}
