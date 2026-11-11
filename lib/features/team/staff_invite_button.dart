import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';

class StaffInviteButton extends StatelessWidget {
  const StaffInviteButton({
    super.key,
    required this.appState,
  });

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        if (appState.currentProfile?.role != UserRole.superAdmin) {
          return const SizedBox.shrink();
        }

        return FilledButton.tonalIcon(
          onPressed: appState.loading || appState.companies.isEmpty
              ? null
              : () => _open(context),
          icon: const Icon(Icons.key_rounded),
          label: Text(appState.tr('shared_company_code')),
        );
      },
    );
  }

  Future<void> _open(BuildContext context) async {
    if (appState.currentProfile?.role != UserRole.superAdmin ||
        appState.companies.isEmpty) {
      return;
    }

    String? selectedCompanyId = appState.companies.first.id;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AnimatedBuilder(
              animation: appState,
              builder: (context, _) {
                final canView =
                    appState.currentProfile?.role == UserRole.superAdmin;

                final companies = canView
                    ? List<Company>.of(appState.companies)
                    : <Company>[];

                Company? selectedCompany;

                for (final company in companies) {
                  if (company.id == selectedCompanyId) {
                    selectedCompany = company;
                    break;
                  }
                }

                if (selectedCompany == null && companies.isNotEmpty) {
                  selectedCompany = companies.first;
                }

                final code = selectedCompany?.joinPassword.trim() ?? '';

                return AlertDialog(
                  title: Text(appState.tr('shared_company_code')),
                  content: SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (companies.isNotEmpty) ...[
                            DropdownButtonFormField<String>(
                              key: ValueKey(selectedCompany?.id),
                              initialValue: selectedCompany?.id,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: appState.tr('company_name'),
                                prefixIcon:
                                const Icon(Icons.apartment_rounded),
                              ),
                              items: companies.map((company) {
                                return DropdownMenuItem<String>(
                                  value: company.id,
                                  child: Text(
                                    company.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value == null) return;

                                setDialogState(() {
                                  selectedCompanyId = value;
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            Text(
                              appState.tr('shared_company_code'),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              code.isEmpty ? appState.tr('not_set') : code,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ] else
                            Text(
                              appState.tr(
                                canView
                                    ? 'no_companies_yet'
                                    : 'error_permission',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
