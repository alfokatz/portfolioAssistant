import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/memory_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/web_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';

import '../fakes/assistant_fakes.dart';

UserMemory _memory(String id, String content) => UserMemory(
  id: id,
  content: content,
  category: UserMemoryCategory.goal,
  source: UserMemorySource.porty,
  updatedAt: DateTime.utc(2026, 10, 1),
);

/// Una memoria en memoria: lo que harían el provider y Supabase.
class _MemoryStore {
  _MemoryStore([List<UserMemory>? initial]) : memories = [...?initial];

  final List<UserMemory> memories;
  final deleted = <String>[];
  bool full = false;

  Future<UserMemory> save(
    String content,
    UserMemoryCategory category, {
    String? replacesId,
  }) async {
    if (full) throw const UserMemoryLimitReached();
    final memory = UserMemory(
      id: replacesId ?? 'uuid-${memories.length + 1}',
      content: content,
      category: category,
      source: UserMemorySource.porty,
      updatedAt: DateTime.utc(2026, 10, 11),
    );
    memories
      ..removeWhere((m) => m.id == replacesId)
      ..insert(0, memory);
    return memory;
  }

  Future<void> delete(String id) async => deleted.add(id);
}

AssistantToolContext _ctx({
  _MemoryStore? store,
  SubscriptionTier tier = SubscriptionTier.premium,
  InvestorProfile? profile,
}) => AssistantToolContext(
  tier: tier,
  data: fakeDataSources(),
  summary: heldSummary,
  investorProfile: profile,
  loadInvestorProfile: () async => profile,
  userMemories: store?.memories ?? const [],
  saveMemory: store?.save,
  deleteMemory: store?.delete,
  now: DateTime.utc(2026, 10, 11),
);

void main() {
  group('memory tools', () {
    test('remember saves the fact and the turn reports it', () async {
      final store = _MemoryStore();
      final ctx = _ctx(store: store);
      final result = await RememberAboutUserTool(ctx).run({
        'fact': 'Quiere comprarse una MacBook Neo rosa en unos 14 meses',
        'category': 'goal',
      });
      expect(result['status'], 'ok');
      expect(result['saved'], isTrue);
      expect(store.memories.single.category, UserMemoryCategory.goal);
      expect(ctx.rememberedFacts, [
        'Quiere comprarse una MacBook Neo rosa en unos 14 meses',
      ]);

      final notice = AssistantTurnPolicy.noticesFor(
        const TurnOutcome([]),
        profileNudgeAlreadyShown: false,
        rememberedFacts: ctx.rememberedFacts,
      );
      expect(notice.rememberedFacts, hasLength(1));
    });

    test('replaces_id updates the brief fact by its short ref', () async {
      final store = _MemoryStore([
        _memory('a', 'Ahorra 200 USD por mes'),
        _memory('b', 'Quiere viajar a Japón'),
      ]);
      final ctx = _ctx(store: store);
      final brief = PortfolioBrief.build(ctx)[PortfolioBrief.userMemoryKey];
      expect((brief! as List).first, {
        'id': 'm1',
        'fact': 'Ahorra 200 USD por mes',
        'category': 'goal',
        'since': '2026-10-01',
      });

      await RememberAboutUserTool(ctx).run({
        'fact': 'Ahorra 300 USD por mes',
        'category': 'finances',
        'replaces_id': 'm1',
      });
      expect(store.memories.map((m) => m.content), [
        'Ahorra 300 USD por mes',
        'Quiere viajar a Japón',
      ]);
    });

    test('a repeated fact is not saved twice', () async {
      final store = _MemoryStore([_memory('a', 'Prefiere ETFs')]);
      final ctx = _ctx(store: store);
      final result = await RememberAboutUserTool(ctx).run({
        'fact': 'prefiere ETFs',
        'category': 'preference',
      });
      expect(result['saved'], isFalse);
      expect(store.memories, hasLength(1));
      expect(ctx.rememberedFacts, isEmpty);
    });

    test('a full memory is a result the model can explain', () async {
      final store = _MemoryStore()..full = true;
      final result = await RememberAboutUserTool(_ctx(store: store)).run({
        'fact': 'Tiene dos hijos',
        'category': 'life',
      });
      expect(result['status'], 'invalid');
      expect(result['reason'], 'memory_full');
    });

    test('forget deletes by ref; an unknown ref is invalid', () async {
      final store = _MemoryStore([_memory('uuid-x', 'Quiere un auto')]);
      final ctx = _ctx(store: store);
      expect(
        (await ForgetAboutUserTool(ctx).run({'memory_id': 'm1'}))['status'],
        'ok',
      );
      expect(store.deleted, ['uuid-x']);
      expect(
        (await ForgetAboutUserTool(ctx).run({'memory_id': 'm9'}))['reason'],
        'unknown_memory_id',
      );
    });

    test('without memory there is no block and no guidance', () {
      final brief = PortfolioBrief.build(_ctx());
      expect(brief.containsKey(PortfolioBrief.userMemoryKey), isFalse);
      expect(
        AssistantOpenAiService.pinnedContextFor(brief),
        isNot(contains('user_memory')),
      );
      final withMemory = PortfolioBrief.build(
        _ctx(store: _MemoryStore([_memory('a', 'Quiere un auto')])),
      );
      expect(
        AssistantOpenAiService.pinnedContextFor(withMemory),
        contains('Sobre user_memory'),
      );
    });
  });

  group('purchase goals', () {
    test('a short purchase starts from 0 and avoids stocks, whatever the '
        'profile', () async {
      final result = await GetGoalProjectionTool(
        _ctx(
          profile: InvestorProfile(
            risk: RiskTolerance.aggressive,
            horizon: InvestmentHorizon.long,
            objective: InvestmentObjective.growth,
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        ),
      ).run({
        'target_amount': 1200,
        'target_date': '2027-12-01',
        'goal_label': 'MacBook',
        'goal_type': 'purchase',
      });
      expect(result['starting_capital'], 0);
      expect(result['starting_capital_source'], 'assumed_zero');
      expect(result['short_term_purchase'], isTrue);
      final plan = result['plan']! as Map;
      expect(plan['short_term_allocation'], isTrue);
      final classes = [
        for (final a in plan['suggested_allocation']! as List)
          (a as Map)['asset_class'],
      ];
      expect(classes, isNot(contains(PlanAssetClass.equities.label)));
      // Sin ingreso de retiro aunque el label diga cualquier cosa.
      expect(plan.containsKey('income'), isFalse);
    });

    test('stated savings for the purchase are used', () async {
      final result = await GetGoalProjectionTool(_ctx()).run({
        'target_amount': 1200,
        'target_date': '2027-12-01',
        'current_savings': 300,
        'goal_type': 'purchase',
      });
      expect(result['starting_capital'], 300);
      expect(result['starting_capital_source'], 'stated');
    });

    test('the card recomputes the same short-term plan from the inputs', () {
      final inputs = SavingsPlanInputs(
        targetAmount: 1200,
        months: 14,
        currentAmount: 0,
        risk: RiskTolerance.moderate,
        startDate: DateTime.utc(2026, 10, 11),
        shortTerm: true,
      );
      final restored = SavingsPlanInputs.fromJson(inputs.toJson())!;
      expect(restored.shortTerm, isTrue);
      expect(
        SavingsPlan.build(restored).allocation,
        PlanAssumptions.shortTermAllocation,
      );
    });

    test('a long purchase keeps the profile allocation', () async {
      final result = await GetGoalProjectionTool(_ctx()).run({
        'target_amount': 30000,
        'target_date': '2031-10-01',
        'goal_type': 'purchase',
      });
      expect(result['short_term_purchase'], isFalse);
    });
  });

  test('search_web returns the server answer and its sources', () async {
    final web = FakeWebSearch();
    final ctx = AssistantToolContext(
      tier: SubscriptionTier.free,
      data: fakeDataSources(webSearch: web),
      now: DateTime.utc(2026, 10, 11),
    );
    final result = await SearchWebTool(ctx).run({
      'query': 'precio MacBook Neo rosa',
    });
    expect(result['status'], 'ok');
    expect(result['sources'], isNotEmpty);
    expect(web.queries, ['precio MacBook Neo rosa']);
    expect((await SearchWebTool(ctx).run({'query': ''}))['status'], 'failed');
  });

  test('profile notes travel in the brief with the user\'s words', () {
    final profile = InvestorProfile(
      risk: RiskTolerance.conservative,
      horizon: InvestmentHorizon.short,
      objective: InvestmentObjective.specificGoal,
      updatedAt: DateTime.utc(2026, 10, 1),
      notes: const {'objective': 'Comprarme una compu'},
    );
    final brief = InvestorProfileContext.brief(profile, DateTime(2026, 10, 11));
    expect(brief!['notes'], {'objective': 'Comprarme una compu'});
  });
}
