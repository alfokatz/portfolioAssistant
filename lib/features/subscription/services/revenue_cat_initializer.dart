import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class RevenueCatInitializer {
  static Future<RevenueCatService> initialize() async {
    final service = RevenueCatService();
    await service.configure();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null && service.isConfigured) {
      await service.logIn(userId);
    }

    return service;
  }
}
