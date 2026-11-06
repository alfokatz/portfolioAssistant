import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/broker_connect/nav/connect_broker_router.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_feed_cache.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_launch.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/providers/home_widget_sync_provider.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/product_events/providers/app_open_source_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';

/// `false` si la app arrancó sin sesión (el toque del widget se hizo en
/// otro estado: ver [WidgetLaunchListener]). `main.dart` lo fija con la
/// sesión restaurada al arrancar; por defecto, `true`.
final widgetLaunchedWithSessionProvider = Provider<bool>((ref) => true);

/// El toque que abrió la app se atiende una vez por proceso: el shell se
/// vuelve a montar al cerrar e iniciar sesión.
bool _initialHandled = false;

/// Para tests: vuelve a atender un launch inicial.
@visibleForTesting
void resetWidgetLaunchInitialHandled() => _initialHandled = false;

/// Abre lo que corresponde al tocar el widget: el toque que abrió la app
/// desde cerrada y los que llegan con la app viva. Va dentro del shell
/// (sesión iniciada), mismo patrón que `PushOpenListener`.
///
/// Sin ruta nueva de go_router: el deep linking de Flutter sigue apagado y
/// los links del widget (`porty-widget://`) llegan por el canal del plugin.
class WidgetLaunchListener extends ConsumerStatefulWidget {
  const WidgetLaunchListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetLaunchListener> createState() =>
      _WidgetLaunchListenerState();
}

class _WidgetLaunchListenerState extends ConsumerState<WidgetLaunchListener> {
  StreamSubscription<Uri?>? _sub;
  final _deduper = WidgetLaunchDeduper();

  @override
  void initState() {
    super.initState();
    final store = ref.read(homeWidgetStoreProvider);
    _sub = store.launches.listen((uri) => _handle(uri, initial: false));
    if (!_initialHandled) {
      _initialHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        Uri? uri;
        try {
          uri = await store.initialLaunch();
        } catch (_) {}
        if (mounted) _handle(uri, initial: true);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _handle(Uri? uri, {required bool initial}) {
    final launch = WidgetLaunch.parse(uri);
    if (launch == null || !mounted) return;
    if (!_deduper.shouldHandle(uri!)) return;

    // Una pregunta tocada en otro estado (sin sesión) y atendida recién
    // después del login no se manda: el usuario no la eligió con esta
    // cuenta. Se abre el chat vacío.
    if (initial &&
        launch.target == WidgetLaunchTarget.question &&
        !ref.read(widgetLaunchedWithSessionProvider)) {
      ref.read(appOpenSourceProvider.notifier).state = AppOpenSource.widget;
      context.goNamed(AssistantRouter.routeName);
      return;
    }

    // Novedades y avisos tampoco se atienden si el toque se hizo antes del
    // login (otro estado, otra cuenta).
    if (initial &&
        (launch.target.isItem || launch.target.isTeaser) &&
        !ref.read(widgetLaunchedWithSessionProvider)) {
      return;
    }

    final isQuestion = launch.target == WidgetLaunchTarget.question;
    ref.read(appOpenSourceProvider.notifier).state =
        isQuestion ? AppOpenSource.widgetQuestion : AppOpenSource.widget;
    final cached = _cachedItems();
    final tapped = _tappedItem(launch, cached);
    final isNovelty = launch.target.isItem || launch.target.isTeaser;
    final isHome = launch.target == WidgetLaunchTarget.home;
    if (launch.target == WidgetLaunchTarget.chat ||
        isQuestion ||
        isNovelty ||
        isHome) {
      // Ninguna prop lleva ticker, titular, texto de la pregunta ni id.
      ref.read(productEventsProvider).log(ProductEvent.widgetOpened, {
        'platform': ref.read(homeWidgetStoreProvider).platform,
        'size': launch.size,
        'target': launch.target.wire,
        'question_id': launch.questionTemplate?.wire,
        'question_source': launch.questionSource?.wire,
        'item_kind': launch.itemKind?.wire,
        'item_prio': launch.itemPrio,
        'data_age_min': launch.dataAgeMin,
        'positions_hidden': ref.read(widgetPositionsHiddenProvider),
        if (isNovelty) ...{
          'item_rank': launch.rank,
          'item_age_h': tapped == null ? null : _ageHours(tapped),
          'tier': ref.read(subscriptionProvider).tier.name,
        },
      });
    }

    switch (launch.target) {
      case WidgetLaunchTarget.question:
        unawaited(_askQuestion(launch));
      case WidgetLaunchTarget.home:
        context.goNamed(HomeRouter.homeRouteName);
      case WidgetLaunchTarget.chat:
        context.goNamed(AssistantRouter.routeName);
      case WidgetLaunchTarget.addPortfolio:
        // La pantalla de las formas de cargar la cartera (bróker, extracto
        // o a mano), no directo al formulario de una posición.
        context.pushNamed(ConnectBrokerRouter.routeName);
      case WidgetLaunchTarget.news:
      case WidgetLaunchTarget.earnings:
        // Un id que no está en la caché (o venció) no abre nada: queda en la
        // Home y no gasta ninguna consulta.
        if (tapped == null) return;
        WidgetNewsSheet.show(
          context,
          ref,
          items: [tapped, ...cached.where((i) => i.id != tapped.id)],
        );
      case WidgetLaunchTarget.teaserNews:
        _openTeaser(WidgetLockedKind.news, cached);
      case WidgetLaunchTarget.teaserEarnings:
        _openTeaser(WidgetLockedKind.earnings, cached);
      case WidgetLaunchTarget.app:
        break;
    }
  }

  /// Resuelve el `ref` tocado en la caché privada del usuario de ahora y abre
  /// el chat con la pregunta en el idioma activo. Si el `ref` no está, es de
  /// otro usuario o su plantilla no coincide con la de la URL, abre el chat
  /// vacío: no se manda nada.
  Future<void> _askQuestion(WidgetLaunch launch) async {
    String? text;
    try {
      final uid = ref.read(widgetCurrentUserIdProvider)();
      final cached =
          uid == null
              ? null
              : WidgetFeedCache(
                ref.read(sharedPreferencesProvider),
              ).question(uid: uid, ref: launch.questionRef!);
      if (cached != null && cached.template == launch.questionTemplate) {
        final texts = await ref.read(widgetTextsLoaderProvider)(
          AppLanguage.code,
        );
        text = WidgetQuestionText.resolve(
          cached.template,
          cached.args,
          cached.hidden,
          texts,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    if (text == null) {
      context.goNamed(AssistantRouter.routeName);
      return;
    }
    GotoAssistant(
      initialQuestion: text,
      origin: AssistantQuestionOrigin.widget(launch.questionTemplate!.wire),
    ).navigate(context: context);
  }

  /// Los ítems vigentes de la caché privada del usuario de ahora.
  List<WidgetCachedItem> _cachedItems() {
    try {
      final uid = ref.read(widgetCurrentUserIdProvider)();
      if (uid == null) return const [];
      final entry = WidgetItemsCache(
        ref.read(sharedPreferencesProvider),
      ).read(uid: uid);
      return entry?.liveItems(DateTime.now()) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  WidgetCachedItem? _tappedItem(
    WidgetLaunch launch,
    List<WidgetCachedItem> cached,
  ) {
    if (!launch.target.isItem) return null;
    for (final item in cached) {
      if (item.id == launch.itemId) return item;
    }
    return null;
  }

  int _ageHours(WidgetCachedItem item) {
    final since = item.publishedAt;
    return since == null ? 0 : DateTime.now().difference(since).inHours;
  }

  /// El aviso del plan siguiente. Si el plan ya lo incluye, abre la hoja con
  /// las novedades; si no, en Android va al paywall y en iOS (aviso neutro,
  /// sin plan ni pago) a la hoja bloqueada, que abre el paywall ahí adentro.
  Future<void> _openTeaser(
    WidgetLockedKind kind,
    List<WidgetCachedItem> cached,
  ) async {
    // En el arranque en frío el plan puede no haber cargado: esperarlo un
    // momento para no mandar a un Gold al paywall.
    for (var i = 0; i < 30 && ref.read(subscriptionProvider).isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }
    final tier = ref.read(subscriptionProvider).tier;
    final included =
        kind == WidgetLockedKind.news
            ? PlanMatrix.allowsNewsFor(tier, held: true)
            : PlanMatrix.allows(tier, PlanFeature.earnings);
    if (included) {
      final items = [
        for (final i in cached)
          if (i.kind == kind.type) i,
      ];
      if (items.isEmpty) return;
      WidgetNewsSheet.show(context, ref, items: items);
      return;
    }
    if (ref.read(homeWidgetStoreProvider).platform == 'ios') {
      WidgetNewsSheet.show(context, ref, items: const [], locked: kind);
      return;
    }
    ref.read(productEventsProvider).log(ProductEvent.widgetItemAction, {
      'action': 'open_paywall',
      'type': kind.type,
      'from_widget': true,
    });
    SubscriptionPaywallSheet.show(
      context,
      ref,
      reason: kind.reason,
      source: kind.source,
      onUpgraded: () => ref.read(subscriptionProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
