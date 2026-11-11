import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../ads/advertisement_page.dart';

/// Backward-compatible wrapper. The real full media advertisement page lives in
/// `features/ads/advertisement_page.dart`. Keeping this file prevents old imports
/// from breaking while avoiding duplicate/stale logic.
class AdvertisementsPage extends StatelessWidget {
  const AdvertisementsPage({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) => AdvertisementPage(appState: appState);
}
