import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/news_feed/domain/news_bundle.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';

/// Qué se compara: el ticker de una noticia o el tema de una pantalla.
enum NewsCompareSubject { ticker, topic }

/// Las acciones de cada noticia (abrir afuera, "¿Cómo me afecta?", "Qué dice
/// cada medio") con sus eventos. Las comparten el feed, el tema y "Mercado
/// hoy" para que se comporten igual.
abstract final class NewsActions {
  /// Abre [url] afuera (solo https) y anota `news_item_opened`.
  static void read(
    WidgetRef ref,
    String url, {
    required String kind,
    bool preferred = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    ref.read(productEventsProvider).log(ProductEvent.newsItemOpened, {
      'kind': kind,
      'preferred': preferred,
    });
    ref.read(dailyBriefUrlLauncherProvider)(uri).catchError((_) => false);
  }

  /// "¿Cómo me afecta?": abre el chat con la pregunta de plantilla.
  ///
  /// Hoy viaja solo la pregunta; cuando el chat sume `PortyScreen.newsItem`
  /// y `PortyScreenContext.news`, se pasa [title] y compañía acá (único
  /// lugar).
  static void askAffects(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String from,
  }) {
    ref.read(productEventsProvider).log(ProductEvent.newsHowAffectsTapped, {
      'from': from,
    });
    GotoAssistant(
      initialQuestion: 'news_ask_affects'.tr(namedArgs: {'title': title}),
    ).navigate(context: context);
  }

  /// Si el plan deja comparar medios: Premium solo tickers en cartera, Gold
  /// tickers y temas. El servidor lo vuelve a validar.
  static bool canCompare(
    WidgetRef ref, {
    required NewsCompareSubject kind,
    bool held = true,
  }) {
    final tier = ref.read(dailyBriefTierProvider);
    return switch (kind) {
      NewsCompareSubject.ticker => PlanMatrix.allowsNewsFor(tier, held: held),
      NewsCompareSubject.topic => PlanMatrix.allows(tier, PlanFeature.news),
    };
  }

  /// "Qué dice cada medio": con plan, abre el chat con la pregunta de
  /// plantilla; sin plan, el paywall (sin nombrar ningún ticker).
  static void compare(
    BuildContext context,
    WidgetRef ref, {
    required String subject,
    required NewsCompareSubject kind,
    required String from,
    bool held = true,
  }) {
    final allowed = canCompare(ref, kind: kind, held: held);
    ref.read(productEventsProvider).log(ProductEvent.newsCompareTapped, {
      'from': from,
      'subject_kind': kind.name,
      'locked': !allowed,
    });
    if (!allowed) {
      openPaywall(
        context,
        ref,
        source: PaywallSource.newsCompare,
        reason:
            kind == NewsCompareSubject.ticker
                ? PaywallReason.heldNews
                : PaywallReason.goldRequired,
      );
      return;
    }
    GotoAssistant(
      initialQuestion: 'news_ask_compare'.tr(namedArgs: {'subject': subject}),
    ).navigate(context: context);
  }

  static void openPaywall(
    BuildContext context,
    WidgetRef ref, {
    required String source,
    PaywallReason reason = PaywallReason.heldNews,
  }) {
    PortyHapticsService.maybeOf(context)?.lockedTap();
    SubscriptionPaywallSheet.show(
      context,
      ref,
      reason: reason,
      source: source,
      onUpgraded: () => ref.read(subscriptionProvider.notifier).refresh(),
    );
  }

  /// El video se abrió (en el reproductor o en YouTube): `news_video_opened`.
  static void videoOpened(WidgetRef ref, NewsVideo video) =>
      ref.read(productEventsProvider).log(ProductEvent.newsVideoOpened, {
        'kind': video.topicId == null ? 'market' : 'topic',
      });
}
