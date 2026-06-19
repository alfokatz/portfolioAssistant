import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final revenueCatServiceProvider = Provider<RevenueCatService>(
  (ref) => RevenueCatService(),
);

/// Sincroniza `app_user_id` de RevenueCat con el `user.id` de Supabase Auth.
final revenueCatAuthSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<Session?>>(authSessionProvider, (previous, next) {
    final service = ref.read(revenueCatServiceProvider);
    if (!service.isConfigured) return;

    final previousId = previous?.value?.user.id;
    final nextId = next.value?.user.id;

    if (nextId != null && nextId != previousId) {
      unawaited(service.logIn(nextId));
      return;
    }

    if (nextId == null && previousId != null) {
      unawaited(service.logOut());
    }
  });
});
