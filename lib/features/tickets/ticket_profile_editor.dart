import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'ticket_text.dart';

Future<void> editTicketProfile(BuildContext context, AppState state) async {
  final profile = state.currentProfile;
  if (profile == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TicketProfileSheet(appState: state, profile: profile),
  );
}

class _TicketProfileSheet extends StatefulWidget {
  const _TicketProfileSheet({required this.appState, required this.profile});
  final AppState appState;
  final Profile profile;

  @override
  State<_TicketProfileSheet> createState() => _TicketProfileSheetState();
}

class _TicketProfileSheetState extends State<_TicketProfileSheet> {
  final _form = GlobalKey<FormState>(debugLabel: 'ticket-contact-form');
  late final List<TextEditingController> _fields;
  bool _saving = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _fields = [p.firstName, p.lastName, p.phone, p.neighborhood, p.street, p.houseNumber]
        .map((text) => TextEditingController(text: text)).toList();
  }

  @override
  void dispose() {
    for (final controller in _fields) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _closing || !(_form.currentState?.validate() ?? false)) return;
    final values = _fields.map((c) => c.text.trim()).toList(growable: false);
    setState(() => _saving = true);
    try {
      await widget.appState.client.rpc('servicepro_save_ticket_contact', params: {
        'p_first': values[0], 'p_last': values[1], 'p_phone': values[2],
        'p_neighborhood': values[3], 'p_street': values[4], 'p_house': values[5],
      });
      final p = widget.profile;
      p.firstName = values[0]; p.lastName = values[1]; p.phone = values[2];
      p.neighborhood = values[3]; p.street = values[4]; p.houseNumber = values[5];
      if (!mounted) return;
      setState(() { _saving = false; _closing = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ticketText(context, 'save_error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.appState;
    return PopScope(
      canPop: !_saving,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(ticketText(context, 'contact'), style: Theme.of(context).textTheme.titleLarge),
                for (var i = 0; i < _fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextFormField(
                      key: ValueKey(i),
                      controller: _fields[i],
                      enabled: !_saving && !_closing,
                      keyboardType: i == 2 ? TextInputType.phone : TextInputType.text,
                      decoration: InputDecoration(labelText: i < 3
                          ? state.tr(['first_name', 'last_name', 'phone'][i])
                          : ticketText(context, ['neighborhood', 'street', 'house'][i - 3])),
                      validator: (text) => text == null || text.trim().isEmpty
                          ? state.tr('fill_required') : null,
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving || _closing ? null : _save,
                  child: Text(state.tr('save')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
