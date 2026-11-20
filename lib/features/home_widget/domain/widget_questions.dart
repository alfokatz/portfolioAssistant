import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';

/// Las plantillas de pregunta del widget: lista cerrada. El `wire` viaja en
/// la URL y en `question_id` de los eventos; el texto sale de las
/// traducciones (`home_widget_<textKey>`), nunca de la URL.
///
/// Redacción: preguntas para entender, sin verbos de acción sobre el
/// usuario (docs/specs/home-widget-v2-tech.md §4.4). Una plantilla nueva
/// vuelve a pasar por compliance.
enum WidgetQuestionTemplate {
  newsWhat('news_what', 'question_news_why', null, PlanFeature.heldNews),
  earningsLast(
    'earnings_last',
    'q_earnings_last',
    null,
    PlanFeature.earnings,
  ),
  moverToday('mover_today', 'q_mover_today', null, PlanFeature.ownPortfolio),
  moverLast('mover_last', 'q_mover_last', null, PlanFeature.ownPortfolio),
  goalProgress(
    'goal_progress',
    'q_goal_progress',
    'q_goal_progress_hidden',
    PlanFeature.goals,
  ),
  planFar(
    'plan_far',
    'q_plan_far',
    'q_plan_far_hidden',
    PlanFeature.allocationPlan,
  ),
  biggest(
    'biggest',
    'q_biggest',
    'q_biggest_hidden',
    PlanFeature.ownPortfolio,
  ),
  alertWeek('alert_week', 'q_alert_week', null, PlanFeature.ownPortfolio),
  sinceBought(
    'since_bought',
    'q_since_bought',
    null,
    PlanFeature.ownPortfolio,
  ),
  topicSince('topic_since', 'q_topic_since', null, PlanFeature.marketData),
  profile(
    'profile',
    'q_profile',
    'q_profile_hidden',
    PlanFeature.ownPortfolio,
  );

  const WidgetQuestionTemplate(
    this.wire,
    this.textKey,
    this.hiddenKey,
    this.requires,
  );

  final String wire;

  /// Clave dentro de `home_widget_*`.
  final String textKey;

  /// Variante sin ticker ni meta (posiciones ocultas); `null` si no tiene.
  final String? hiddenKey;

  /// La capacidad del plan que hace falta (para no mandar al usuario a una
  /// respuesta bloqueada).
  final PlanFeature requires;

  /// Clave completa en es-ES.json / en-US.json (para `.tr()`).
  String get translationKey => 'home_widget_$textKey';

  static WidgetQuestionTemplate? fromWire(String? wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

/// De dónde sale la pregunta (prop `question_source` de los eventos).
enum WidgetQuestionSource {
  novelty,
  goal,
  plan,
  biggest,
  profile;

  String get wire => name;

  static WidgetQuestionSource? fromWire(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// El texto de una pregunta en un idioma. Lo usan el builder (al armar el
/// snapshot) y el listener (al resolver el `ref` tocado).
abstract final class WidgetQuestionText {
  /// [args]: `ticker`, `goal` (el nombre de la meta tal cual) y `risk` (el
  /// `wire` del perfil: `conservative` | `moderate` | `aggressive`).
  static String resolve(
    WidgetQuestionTemplate template,
    Map<String, String> args,
    bool hidden,
    WidgetTexts texts,
  ) {
    final key =
        hidden && template.hiddenKey != null
            ? template.hiddenKey!
            : template.textKey;
    final risk = args['risk'];
    return texts.get(key, {
      if (args['ticker'] != null) 'ticker': args['ticker']!,
      if (args['goal'] != null) 'goal': args['goal']!,
      if (risk != null) 'risk': texts.get('profile_risk_$risk'),
    });
  }
}

/// Una pregunta todavía sin texto: plantilla + datos del usuario.
class WidgetQuestionDraft {
  const WidgetQuestionDraft({
    required this.template,
    required this.source,
    required this.subject,
    this.args = const {},
  });

  final WidgetQuestionTemplate template;
  final WidgetQuestionSource source;

  /// De qué habla (`t:NVDA`, `goal:Viaje`, `profile`...): dos preguntas del
  /// mismo sujeto no se muestran juntas.
  final String subject;

  /// Datos crudos: `ticker`, `goal`, `risk`. Vacío en la variante oculta.
  final Map<String, String> args;

  /// 8 hex, determinístico: `q|<wire>|<args ordenados>|<hidden>`.
  String ref({required bool hidden}) {
    final keys = args.keys.toList()..sort();
    final encoded = [for (final k in keys) '$k=${args[k]}'].join(',');
    return WidgetItemsSelector.itemId('q|${template.wire}|$encoded|$hidden');
  }

  WidgetQuestionRef toRef(WidgetTexts texts, {required bool hidden}) =>
      WidgetQuestionRef(
        ref: ref(hidden: hidden),
        template: template.wire,
        source: source.wire,
        text: WidgetQuestionText.resolve(template, args, hidden, texts),
      );

  /// Lo que se guarda en la caché privada para resolver el toque.
  Map<String, Object?> cacheJson({required bool hidden}) => {
    't': template.wire,
    'args': args,
    'hidden': hidden,
  };
}

/// Los datos del usuario de los que salen las preguntas generales.
class WidgetQuestionContext {
  const WidgetQuestionContext({
    required this.tier,
    this.goalLabel,
    this.hasDrift = false,
    this.driftTicker,
    this.biggestTicker,
    this.profileRisk,
  });

  final SubscriptionTier tier;

  /// La meta del primer aviso de meta o, si no, la activa con fecha más
  /// cercana. `null` = no hay metas.
  final String? goalLabel;

  /// Hay desvío del plan de cartera; [driftTicker] es el que más se alejó.
  final bool hasDrift;
  final String? driftTicker;

  /// La posición más grande; `null` con menos de 2 posiciones.
  final String? biggestTicker;

  /// `conservative` | `moderate` | `aggressive`; `null` sin perfil.
  final String? profileRisk;
}

class WidgetQuestionsResult {
  const WidgetQuestionsResult({required this.questions, required this.drafts});

  final WidgetQuestions questions;

  /// Todo lo que quedó en el snapshot (para la caché privada de `ref`).
  final List<WidgetQuestionDraft> drafts;
}

/// Arma las preguntas del widget. Sin IA, sin pregunta genérica: cada texto
/// nombra un ticker, una meta o un dato del usuario; si no hay dato, esa
/// fuente no existe.
abstract final class WidgetQuestionsBuilder {
  static const largeMax = 2;

  static bool _allowed(SubscriptionTier tier, WidgetQuestionTemplate t) =>
      PlanMatrix.allows(tier, t.requires);

  static String _tickerSubject(String ticker) => 't:${ticker.toUpperCase()}';

  // --- La pregunta de cada novedad ---

  static WidgetQuestionDraft? _novelty(
    SubscriptionTier tier,
    WidgetQuestionTemplate template,
    String subject,
    Map<String, String> args,
  ) {
    if (!_allowed(tier, template)) return null;
    return WidgetQuestionDraft(
      template: template,
      source: WidgetQuestionSource.novelty,
      subject: subject,
      args: args,
    );
  }

  static WidgetQuestionDraft? forNews(SubscriptionTier tier, String ticker) =>
      _novelty(
        tier,
        WidgetQuestionTemplate.newsWhat,
        _tickerSubject(ticker),
        {'ticker': ticker},
      );

  static WidgetQuestionDraft? forEarnings(
    SubscriptionTier tier,
    String ticker,
  ) => _novelty(
    tier,
    WidgetQuestionTemplate.earningsLast,
    _tickerSubject(ticker),
    {'ticker': ticker},
  );

  static WidgetQuestionDraft? forMover(
    SubscriptionTier tier,
    String ticker, {
    required bool today,
  }) => _novelty(
    tier,
    today
        ? WidgetQuestionTemplate.moverToday
        : WidgetQuestionTemplate.moverLast,
    _tickerSubject(ticker),
    {'ticker': ticker},
  );

  static WidgetQuestionDraft? forBiggest(
    SubscriptionTier tier,
    String ticker,
  ) => _novelty(
    tier,
    WidgetQuestionTemplate.biggest,
    _tickerSubject(ticker),
    {'ticker': ticker},
  );

  /// Pregunta de un aviso de la Home: [template] ya viene elegida por kind.
  static WidgetQuestionDraft? forInsight(
    SubscriptionTier tier,
    WidgetQuestionTemplate template, {
    String? ticker,
    String? goal,
  }) {
    final isGoal = template == WidgetQuestionTemplate.goalProgress;
    final value = isGoal ? goal : ticker;
    if (value == null || value.isEmpty) return null;
    return _novelty(
      tier,
      template,
      isGoal ? 'goal:$value' : _tickerSubject(value),
      isGoal ? {'goal': value} : {'ticker': value},
    );
  }

  // --- Generales (en este orden) ---

  static List<WidgetQuestionDraft> generals(
    WidgetQuestionContext ctx, {
    required bool hidden,
  }) {
    WidgetQuestionDraft? draft(
      WidgetQuestionTemplate template,
      WidgetQuestionSource source,
      String subject,
      Map<String, String> args,
    ) =>
        _allowed(ctx.tier, template)
            ? WidgetQuestionDraft(
              template: template,
              source: source,
              subject: subject,
              args: hidden ? const {} : args,
            )
            : null;

    final goal = ctx.goalLabel;
    final driftTicker = ctx.driftTicker;
    final biggest = ctx.biggestTicker;
    final risk = ctx.profileRisk;
    final out = <WidgetQuestionDraft?>[
      if (goal != null && goal.isNotEmpty)
        draft(
          WidgetQuestionTemplate.goalProgress,
          WidgetQuestionSource.goal,
          hidden ? 'goal' : 'goal:$goal',
          {'goal': goal},
        ),
      if (ctx.hasDrift && (hidden || (driftTicker?.isNotEmpty ?? false)))
        draft(
          WidgetQuestionTemplate.planFar,
          WidgetQuestionSource.plan,
          hidden ? 'plan' : _tickerSubject(driftTicker!),
          {'ticker': driftTicker ?? ''},
        ),
      if (biggest != null && biggest.isNotEmpty)
        draft(
          WidgetQuestionTemplate.biggest,
          WidgetQuestionSource.biggest,
          hidden ? 'biggest' : _tickerSubject(biggest),
          {'ticker': biggest},
        ),
      if (risk != null)
        draft(
          WidgetQuestionTemplate.profile,
          WidgetQuestionSource.profile,
          'profile',
          {'risk': risk},
        ),
    ];
    return [
      for (final d in out)
        // Con posiciones ocultas solo valen las que tienen variante oculta.
        if (d != null && (!hidden || d.template.hiddenKey != null)) d,
    ];
  }

  /// `fallback` = primera general cuyo sujeto no es el de [head]; `large` =
  /// [head] (si trae pregunta) + generales de sujetos distintos, hasta 2.
  /// Con [hidden], [head] debe venir en `null`.
  static WidgetQuestionsResult build({
    required WidgetQuestionContext ctx,
    required bool hidden,
    required WidgetQuestionDraft? head,
    required WidgetTexts texts,
  }) {
    final all = generals(ctx, hidden: hidden);
    final headSubject = head?.subject;
    WidgetQuestionDraft? fallback;
    for (final g in all) {
      if (g.subject != headSubject) {
        fallback = g;
        break;
      }
    }
    final large = <WidgetQuestionDraft>[if (head != null) head];
    final subjects = <String>{if (headSubject != null) headSubject};
    for (final g in all) {
      if (large.length >= largeMax) break;
      if (subjects.add(g.subject)) large.add(g);
    }
    final shown = <WidgetQuestionDraft>[if (fallback != null) fallback, ...large];
    return WidgetQuestionsResult(
      questions: WidgetQuestions(
        fallback: fallback?.toRef(texts, hidden: hidden),
        large: [for (final q in large) q.toRef(texts, hidden: hidden)],
      ),
      drafts: shown,
    );
  }
}
