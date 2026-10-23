import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/models/manage_action.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/manage_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/report_tools.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';

import '../fakes/assistant_fakes.dart';

class _Quotes implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) async =>
      const Right(100);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String t,
  ) async => const Right([]);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String t) async => const [];
}

AssistantToolContext _ctx({
  SubscriptionTier tier = SubscriptionTier.premium,
  List<Map<String, Object?>> watchlist = const [],
  List<Map<String, Object?>> alerts = const [],
  AllocationPlan? plan,
  Map<String, Object?> settings = const {'theme': 'system', 'haptics': true},
  bool withMemories = false,
  Map<String, String> accounts = const {
    'etoro': 'connected',
    'binance': 'not_connected',
  },
}) => AssistantToolContext(
  tier: tier,
  data: fakeDataSources(quotes: _Quotes()),
  summary: heldSummary,
  loadWatchlist: () async => watchlist,
  loadPriceAlerts: () async => alerts,
  loadAllocationPlan: () async => plan,
  loadAppSettings: () async => settings,
  loadConnectedAccounts: () async => accounts,
  userMemories: [
    if (withMemories)
      UserMemory(
        id: 'm1',
        content: 'Ahorra para un auto',
        category: UserMemoryCategory.goal,
        source: UserMemorySource.porty,
        updatedAt: DateTime(2026, 10, 1),
      ),
  ],
  now: DateTime(2026, 10, 22),
);

const _watchlist = [
  {'ticker': 'AMZN', 'alerts_on': true},
  {'ticker': 'NFLX', 'alerts_on': false},
];

const _alerts = [
  {
    'id': 'a1',
    'symbol': 'VOO',
    'condition': 'above',
    'target': 750,
    'status': 'active',
  },
  {
    'id': 'a2',
    'symbol': 'NVDA',
    'condition': 'pct_down',
    'target': 10,
    'status': 'paused',
  },
  {
    'id': 'a3',
    'symbol': 'NVDA',
    'condition': 'above',
    'target': 200,
    'status': 'active',
  },
];

void main() {
  test('son tools de propuesta (la card las reconoce)', () {
    expect(ActionTools.proposalTools.containsAll(ManageTools.names), isTrue);
    expect(ManageTools.names, isNot(contains(ManageTools.getAppSettings)));
  });

  group('propose_watchlist_change', () {
    Future<Map<String, Object?>> run(
      Map<String, Object?> args, {
      SubscriptionTier tier = SubscriptionTier.premium,
    }) => ProposeWatchlistChangeTool(
      _ctx(tier: tier, watchlist: _watchlist),
    ).run(args);

    test('propone dejar de seguir (no escribe)', () async {
      final r = await run({'ticker': 'amzn', 'change': 'remove'});
      expect(r['status'], 'ok');
      expect(r[AnswerGuide.key], ActionGuides.ok);
      final p = ActionProposal.fromToolResult(r)!;
      expect(p.kind, ActionKind.manage);
      expect(p.manageOp, ManageOp.unwatch);
      expect(p.ticker, 'AMZN');
    });

    test(
      'avisos: propone el cambio; si ya está así, no hay nada que hacer',
      () async {
        final off =
            ActionProposal.fromToolResult(
              await run({'ticker': 'AMZN', 'change': 'alerts_off'}),
            )!;
        expect(off.manageOp, ManageOp.watchNotifyOff);
        expect(
          (await run({'ticker': 'NFLX', 'change': 'alerts_off'}))['status'],
          'no_change',
        );
      },
    );

    test('lo que no sigue, Free y faltantes', () async {
      final r = await run({'ticker': 'TSLA', 'change': 'remove'});
      expect(r['status'], 'not_on_watchlist');
      expect(r['items'], ['AMZN', 'NFLX']);
      expect(
        (await run({
          'ticker': 'AMZN',
          'change': 'remove',
        }, tier: SubscriptionTier.free))['status'],
        'locked',
      );
      expect((await run({'ticker': 'AMZN'}))['status'], 'needs_input');
    });
  });

  group('propose_alert_change', () {
    Future<Map<String, Object?>> run(Map<String, Object?> args) =>
        ProposeAlertChangeTool(_ctx(alerts: _alerts)).run(args);

    test('por ticker con una sola alerta: propone, con su nombre', () async {
      final r = await run({'ticker': 'voo', 'change': 'delete'});
      final p = ActionProposal.fromToolResult(r)!;
      expect(p.manageOp, ManageOp.alertDelete);
      expect(p.targetId, 'a1');
      expect(p.ticker, 'VOO');
      expect(p.targetLabel, startsWith('VOO sube a'));
    });

    test(
      'varias alertas del ticker: pregunta cuál; con el id, propone',
      () async {
        final r = await run({'ticker': 'NVDA', 'change': 'delete'});
        expect(r['status'], 'ambiguous');
        expect((r['candidates'] as List).length, 2);
        expect(r[AnswerGuide.key], ManageGuides.alertAmbiguous);
        final p =
            ActionProposal.fromToolResult(
              await run({'alert_id': 'a2', 'change': 'resume'}),
            )!;
        expect(p.manageOp, ManageOp.alertResume);
        expect(p.targetLabel, 'NVDA baja 10%');
      },
    );

    test('ya pausada, inexistente y faltantes', () async {
      expect(
        (await run({'alert_id': 'a2', 'change': 'pause'}))['status'],
        'no_change',
      );
      expect(
        (await run({'ticker': 'TSLA', 'change': 'pause'}))['status'],
        'not_found',
      );
      expect((await run({'change': 'pause'}))['status'], 'needs_input');
    });
  });

  test('la card escribe sus textos (el modelo no)', () {
    const t = ManageTarget(ticker: 'VOO', id: 'a1', label: 'VOO sube a \$750');
    expect(ManageOp.alertDelete.describe(t), contains('VOO sube a \$750'));
    expect(ManageOp.unwatch.confirmLabel(t), 'Dejar de seguir VOO');
    expect(ManageOp.unwatch.destructive, isTrue);
    expect(ManageOp.alertPause.link, ManageLink.alerts);
  });

  group('propose_allocation_plan', () {
    Future<Map<String, Object?>> run(
      Map<String, Object?> args, {
      SubscriptionTier tier = SubscriptionTier.premium,
      AllocationPlan? plan,
    }) => ProposeAllocationPlanTool(_ctx(tier: tier, plan: plan)).run(args);

    test('el plan que dice el usuario, en una card', () async {
      final p =
          ActionProposal.fromToolResult(
            await run({
              'targets': [
                {'ticker': 'voo', 'pct': 60},
                {'ticker': 'BND', 'pct': 40},
              ],
              'frequency': 'monthly',
            }),
          )!;
      expect(p.manageOp, ManageOp.allocationSave);
      expect(p.manageTarget.targets, {'VOO': 60.0, 'BND': 40.0});
      expect(
        p.manageOp!.describe(p.manageTarget),
        contains('VOO 60% · BND 40%'),
      );
    });

    test('si no suma 100 no decide: pregunta', () async {
      final r = await run({
        'targets': [
          {'ticker': 'VOO', 'pct': 60},
          {'ticker': 'BND', 'pct': 30},
        ],
      });
      expect(r['status'], 'invalid');
      expect(r['sum'], 90);
      expect(r[AnswerGuide.key], ManageGuides.allocationSum);
    });

    test('solo los avisos: necesita un plan guardado', () async {
      expect((await run({'alerts': 'off'}))['reason'], 'no_plan');
      final p =
          ActionProposal.fromToolResult(
            await run({
              'drift_threshold': 8,
            }, plan: const AllocationPlan(targets: {'VOO': 100})),
          )!;
      expect(p.params['threshold'], 8);
      expect(p.manageTarget.targets, isEmpty);
    });

    test('Free bloqueado y sin nada pide el dato', () async {
      expect(
        (await run({'alerts': 'on'}, tier: SubscriptionTier.free))['status'],
        'locked',
      );
      expect((await run({}))['status'], 'needs_input');
    });
  });

  group('ajustes', () {
    test('solo lo que cambia, en una card con sus nombres', () async {
      final r = await ProposeSettingsChangeTool(_ctx()).run({
        'theme': 'dark',
        'haptics': true,
        'currency': 'uyu',
        'notify_earnings': false,
      });
      final p = ActionProposal.fromToolResult(r)!;
      expect(p.manageOp, ManageOp.settingsChange);
      // La vibración ya estaba prendida: no se propone.
      expect(p.manageTarget.changes, {
        'theme': 'dark',
        'currency': 'UYU',
        'notify_earnings': false,
      });
      final text = p.manageOp!.describe(p.manageTarget);
      expect(text, contains('• Tema: oscuro'));
      expect(text, contains('• Avisos de resultados de tus empresas: apagado'));
    });

    test('valores inválidos, nada que cambiar y faltantes', () async {
      final tool = ProposeSettingsChangeTool(_ctx());
      expect(
        (await tool.run({'quiet_hours': '25:00-07:00'}))['reason'],
        'invalid_arguments',
      );
      expect(
        (await tool.run({'currency': 'XYZ'}))['reason'],
        'invalid_arguments',
      );
      expect((await tool.run({'theme': 'system'}))['status'], 'no_change');
      expect((await tool.run({}))['status'], 'needs_input');
    });

    test(
      'get_app_settings lee y propose_memory_clear pide confirmar',
      () async {
        final read = await GetAppSettingsTool(_ctx()).run({});
        expect((read['settings'] as Map)['theme'], 'system');
        expect(
          (await ProposeMemoryClearTool(_ctx()).run({}))['status'],
          'empty',
        );
        final p =
            ActionProposal.fromToolResult(
              await ProposeMemoryClearTool(_ctx(withMemories: true)).run({}),
            )!;
        expect(p.manageOp, ManageOp.memoryClear);
        expect(p.manageOp!.destructive, isTrue);
      },
    );
  });

  group('propose_broker_action', () {
    Future<Map<String, Object?>> run(
      Map<String, Object?> args, {
      SubscriptionTier tier = SubscriptionTier.premium,
      Map<String, String>? accounts,
    }) => ProposeBrokerActionTool(
      accounts == null
          ? _ctx(tier: tier)
          : _ctx(tier: tier, accounts: accounts),
    ).run(args);

    test(
      'actualizar y desconectar (pregunta qué hacer con lo importado)',
      () async {
        final sync =
            ActionProposal.fromToolResult(
              await run({'broker': 'etoro', 'action': 'sync'}),
            )!;
        expect(sync.manageOp, ManageOp.brokerSync);
        expect(
          (await run({'broker': 'etoro', 'action': 'disconnect'}))['missing'],
          ['keep_positions'],
        );
        final off =
            ActionProposal.fromToolResult(
              await run({
                'broker': 'etoro',
                'action': 'disconnect',
                'keep_positions': false,
              }),
            )!;
        expect(off.manageOp!.describe(off.manageTarget), contains('borro'));
        expect(off.manageOp!.destructive, isTrue);
      },
    );

    test('sin conectar, sin acceso y Free', () async {
      expect(
        (await run({'broker': 'binance', 'action': 'sync'}))['status'],
        'not_connected',
      );
      expect(
        (await run(
          {'broker': 'etoro', 'action': 'sync'},
          accounts: const {'etoro': 'reconnect_required'},
        ))['status'],
        'reconnect_required',
      );
      expect(
        (await run({
          'broker': 'etoro',
          'action': 'sync',
        }, tier: SubscriptionTier.free))['status'],
        'locked',
      );
    });
  });

  group('leer todo', () {
    test('get_app_settings trae también la cuenta', () async {
      final ctx = AssistantToolContext(
        tier: SubscriptionTier.premium,
        data: fakeDataSources(quotes: _Quotes()),
        loadAppSettings: () async => {'theme': 'dark'},
        loadAccountOverview:
            () async => {
              'plan': 'premium',
              'queries_used_this_month': 12,
              'achieved_goals': [
                {'label': 'MacBook'},
              ],
            },
      );
      final r = await GetAppSettingsTool(ctx).run({});
      expect((r['settings'] as Map)['theme'], 'dark');
      expect((r['account'] as Map)['plan'], 'premium');
    });

    test('get_weekly_report: el de la Home, o que todavía no está', () async {
      AssistantToolContext ctx(Map<String, Object?>? report) =>
          AssistantToolContext(
            tier: SubscriptionTier.free,
            data: fakeDataSources(quotes: _Quotes()),
            loadWeeklyReport: () async => report,
          );
      final ok = await GetWeeklyReportTool(
        ctx({'week': '2026-10-19', 'change_pct': 2.5, 'reading': 'Buena'}),
      ).run({});
      expect(ok['status'], 'ok');
      expect((ok['report'] as Map)['change_pct'], 2.5);
      expect(ok[AnswerGuide.key], ReportGuides.ok);
      expect(
        (await GetWeeklyReportTool(ctx(null)).run({}))['status'],
        'not_ready',
      );
    });
  });
}
