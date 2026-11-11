import 'package:flutter/material.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// Returns true only after the server has persisted and authorized the profile.
class AccessPage extends StatefulWidget {
  const AccessPage({super.key, required this.appState, this.organization = false});
  final AppState appState;
  final bool organization;
  @override
  State<AccessPage> createState() => _AccessPageState();
}

class _AccessPageState extends State<AccessPage> {
  final form = GlobalKey<FormState>(debugLabel: 'access-form');
  final first = TextEditingController();
  final last = TextEditingController();
  final phone = TextEditingController(text: '+998');
  final password = TextEditingController();
  final companyCode = TextEditingController();
  final neighborhood = TextEditingController();
  final street = TextEditingController();
  final house = TextEditingController();
  final job = TextEditingController();
  final email = TextEditingController();
  String? companyId;
  String? error;
  bool directoryLoading = true;
  bool busy = false;
  bool register = true;
  bool legacy = false;
  bool reveal = false;
  UserRole role = UserRole.director;
  String t(String key) => widget.appState.tr(key);

  @override
  void initState() {
    super.initState();
    register = !widget.organization;
    _load();
  }
  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      directoryLoading = true;
      error = null;
    });

    try {
      await widget.appState.loadPublicCompanies();

      if (!mounted) return;

      final list = widget.appState.publicCompanies;
      setState(() {
        companyId = list.isEmpty ? null : list.first.id;
      });
    } catch (e, stack) {
      debugPrint('Tashkilotlarni yuklash xatosi: $e');
      debugPrintStack(stackTrace: stack);

      if (!mounted) return;

      setState(() {
        error = t('directory_failed');
      });


    } finally {
      if (mounted) {
        setState(() => directoryLoading = false);
      }
    }
  }
  @override
  void dispose() {
    for (final c in [first, last, phone, password, companyCode, neighborhood, street, house, job, email]) { c.dispose(); }
    super.dispose();
  }
  Widget field(TextEditingController controller, String key, IconData icon, {TextInputType? keyboard, bool secret = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        key: ValueKey(key),
        controller: controller, enabled: !busy,
        keyboardType: keyboard, obscureText: secret && !reveal,
        autocorrect: !secret, enableSuggestions: !secret,
        textInputAction: TextInputAction.next,
        validator: (v) => v == null || v.trim().isEmpty ? t('fill_required') : null,
        decoration: InputDecoration(labelText: t(key), prefixIcon: Icon(icon),
          suffixIcon: secret ? IconButton(onPressed: () => setState(() => reveal = !reveal),
            tooltip: t(reveal ? 'hide_password' : 'show_password'),
            icon: Icon(reveal ? Icons.visibility_off : Icons.visibility)) : null),
      ),
    );
  }
  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    if (!legacy && companyId == null) { setState(() => error = t('directory_failed')); return; }
    setState(() { busy = true; error = null; });
    final state = widget.appState;
    final bool ok;
    if (legacy) {
      ok = await state.legacyAccess(email.text, password.text);
    } else if (widget.organization) {
      ok = await state.staffAccess(companyId: companyId!, role: role,
        firstName: first.text, lastName: last.text, password: password.text,
        jobTitle: job.text, firstAccess: register, companyCode: companyCode.text);
    } else {
      ok = await state.residentAccess(register: register, companyId: companyId!,
        phone: phone.text, password: password.text, firstName: first.text,
        lastName: last.text, neighborhood: neighborhood.text, street: street.text, houseNumber: house.text);
    }
    if (!mounted) return;
    if (ok) {
      setState(() => busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).pop(true);
        }
      });
    }
    else { setState(() { busy = false; error = state.errorMessage ?? t('error_unknown'); }); }
  }
  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: !busy, child: Scaffold(
      appBar: AppBar(title: Text(t(widget.organization ? 'organization_access' : 'resident_profile'))),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 580),
        child: Form(key: form, child: ListView(padding: const EdgeInsets.all(20), children: [
          Icon(widget.organization ? Icons.apartment_rounded : Icons.person_outline_rounded,
            size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(t(legacy ? 'legacy_help' : widget.organization ? 'staff_help' : 'resident_help')),
          const SizedBox(height: 20),
          if (!legacy) ...[
            SegmentedButton<bool>(segments: [
              ButtonSegment(value: true, label: Text(t('first_access'))),
              ButtonSegment(value: false, label: Text(t('login'))),
            ], selected: {register}, onSelectionChanged: busy ? null : (s) => setState(() { register = s.first; error = null; })),
            const SizedBox(height: 20),
            if (directoryLoading) const LinearProgressIndicator()
            else DropdownButtonFormField<String>(
              key: const ValueKey('access-company'),
              initialValue: companyId, isExpanded: true,
              decoration: InputDecoration(labelText: t('company_name'), prefixIcon: const Icon(Icons.apartment)),
              items: widget.appState.publicCompanies.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: busy ? null : (value) => setState(() => companyId = value),
            ),
            if (error != null && widget.appState.publicCompanies.isEmpty)
              TextButton.icon(onPressed: busy ? null : _load, icon: const Icon(Icons.refresh), label: Text(t('retry'))),
            const SizedBox(height: 16),
            if (widget.organization) ...[
              DropdownButtonFormField<UserRole>(key: const ValueKey('access-role'), initialValue: role,
                decoration: InputDecoration(labelText: t('role')),
                items: [UserRole.director, UserRole.admin, UserRole.worker].map((r) => DropdownMenuItem(value: r, child: Text(t(r.dbValue)))).toList(),
                onChanged: busy ? null : (r) => setState(() => role = r!),
              ),
              const SizedBox(height: 16),
            ],
            if (register || widget.organization) ...[
              field(first, 'first_name', Icons.person_outline),
              field(last, 'last_name', Icons.badge_outlined),
            ],
            if (!widget.organization) field(phone, 'phone', Icons.phone_outlined, keyboard: TextInputType.phone),
          ] else field(email, 'email', Icons.email_outlined, keyboard: TextInputType.emailAddress),
          if (widget.organization && !legacy)
            field(companyCode, 'shared_company_code', Icons.apartment_rounded, secret: true),
          field(password, widget.organization && !legacy ? 'personal_password' : 'password', Icons.lock_outline, secret: true),
          if (!legacy && register && !widget.organization) ...[
            field(neighborhood, 'neighborhood', Icons.location_city),
            field(street, 'street_name', Icons.signpost_outlined),
            field(house, 'house_number', Icons.home_outlined),
          ],
          if (!legacy && widget.organization && register && role == UserRole.worker)
            field(job, 'job_title', Icons.engineering_outlined),
          if (error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          FilledButton.icon(onPressed: busy || (!legacy && directoryLoading) ? null : submit,
            icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward),
            label: Text(t(register && !legacy ? 'save_continue' : 'login'))),
          const SizedBox(height: 12),
          TextButton(onPressed: busy ? null : () => setState(() { legacy = !legacy; error = null; }),
            child: Text(t(legacy ? 'back' : 'legacy_login'))),
        ])),
      )),
    ));
  }
}
