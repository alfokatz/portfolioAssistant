import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/shared/loading/button_spinner.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/statement_import/data/statement_import_client.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';
import 'package:portfolio_assistant/features/statement_import/providers/statement_import_provider.dart';
import 'package:portfolio_assistant/features/statement_import/view/import_row_edit_sheet.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/porty_loader.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// Importar posiciones desde un CSV o PDF del bróker, con Porty guiando:
/// pide el archivo (y explica qué sirve), piensa mientras lo lee, cuenta
/// lo que encontró (cada fila se corrige o se descarta) y celebra al
/// terminar. Si algo falla, lo dice él con qué hacer.
class StatementImportScreen extends ConsumerStatefulWidget {
  const StatementImportScreen({super.key, this.startWriting = false});

  /// Abre directo en "Escribilo" (desde el onboarding: "Contale a Porty qué
  /// tenés").
  final bool startWriting;

  @override
  ConsumerState<StatementImportScreen> createState() =>
      _StatementImportScreenState();
}

class _StatementImportScreenState extends ConsumerState<StatementImportScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.startWriting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _write();
      });
    }
  }

  Future<void> _write() async {
    final text = await _NoteSheet.show(context);
    if (text == null || !mounted) return;
    await ref.read(statementImportProvider.notifier).readNote(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(statementImportProvider);
    final notifier = ref.read(statementImportProvider.notifier);
    // Los avatares de ticker leen la paleta del chat.
    QaColors.resolve(Theme.of(context).brightness);

    final Widget body = switch (state.phase) {
      ImportPhase.intro => _Intro(
        errorType: state.errorType,
        onPick: notifier.pickAndRead,
        onPickScreenshot: notifier.pickScreenshotAndRead,
        onWrite: _write,
      ),
      ImportPhase.reading => const _Reading(),
      ImportPhase.preview || ImportPhase.importing => _Preview(state: state),
      ImportPhase.done => _Done(
        imported: state.importedCount,
        importedTickers: [
          for (final t in {for (final r in state.ready) r.ticker})
            if (!state.failedTickers.contains(t)) t,
        ],
        failed: state.failedTickers,
        onAnother: notifier.reset,
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('import_title'.tr()),
        leading: IconButton(
          tooltip: 'import_close'.tr(),
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed(HomeRouter.homeRouteName);
            }
          },
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
          // Importando sigue siendo la vista previa (con el botón cargando).
          child: KeyedSubtree(
            key: ValueKey(
              state.phase == ImportPhase.importing
                  ? ImportPhase.preview
                  : state.phase,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Lo que dice Porty ante un error tipado del servidor (nunca el código):
/// qué pasó y qué hacer.
String importErrorMessage(String type) => switch (type) {
  'file_too_large' => 'statement_import_error_too_large'.tr(),
  'unsupported_type' => 'statement_import_error_unsupported'.tr(),
  'nothing_found' => 'statement_import_error_nothing_found'.tr(),
  'quota_exceeded' ||
  'daily_quota_exceeded' => 'statement_import_error_quota'.tr(),
  'rate_limited' => 'statement_import_error_rate_limited'.tr(),
  'network' => 'statement_import_error_network'.tr(),
  'picker_failed' => 'statement_import_error_picker'.tr(),
  _ => 'statement_import_error_unavailable'.tr(),
};

/// Sufijo de los textos que dicen de dónde salió ("en tu archivo", "en tu
/// captura", "en lo que escribiste").
String _originSuffix(ImportOrigin origin) => switch (origin) {
  ImportOrigin.file => '',
  ImportOrigin.screenshot => '_screenshot',
  ImportOrigin.note => '_note',
};

bool _isQuota(String? type) =>
    type == 'quota_exceeded' || type == 'daily_quota_exceeded';

/// Un ListView con el aire de las pantallas de Porty y, abajo, lo fijo
/// (botones). Cada fase lo arma igual.
class _Layout extends StatelessWidget {
  const _Layout({required this.content, required this.bottom});

  final List<Widget> content;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pageHorizontal,
              AppDimens.sp12,
              AppDimens.pageHorizontal,
              AppDimens.sp24,
            ),
            children: content,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp16,
          ),
          child: bottom,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inicio: Porty pide el archivo (o explica qué falló)
// ---------------------------------------------------------------------------

class _Intro extends ConsumerWidget {
  const _Intro({
    required this.errorType,
    required this.onPick,
    required this.onPickScreenshot,
    required this.onWrite,
  });

  final String? errorType;
  final Future<void> Function() onPick;
  final Future<void> Function() onPickScreenshot;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final error = errorType;
    final quota = _isQuota(error);
    // Tope de consultas o demasiados intentos: el "no" de Porty. El resto
    // (archivo que no sirve, sin conexión) es un traspié: preocupado.
    final mood =
        error == null
            ? PortyAvatarState.idle
            : quota || error == 'rate_limited'
            ? PortyAvatarState.error
            : PortyAvatarState.concerned;
    // Si el archivo era el problema, la fila invita a elegir otro.
    final fileTitle =
        switch (error) {
          'file_too_large' ||
          'unsupported_type' ||
          'nothing_found' => 'statement_import_pick_again',
          _ => 'statement_import_way_file_title',
        }.tr();
    void tap(VoidCallback action) {
      PortyHapticsService.maybeOf(context)?.selectionTap();
      action();
    }

    return _Layout(
      content: [
        PortySays(
          messageKey: error ?? 'intro',
          mood: mood,
          message: Text(
            error == null
                ? 'statement_import_intro_porty'.tr()
                : importErrorMessage(error),
          ),
          footnote:
              error == null
                  ? Text('statement_import_intro_porty_note'.tr())
                  : null,
        ),
        if (quota)
          Padding(
            padding: const EdgeInsets.only(
              left: PortySays.avatarSize + AppDimens.sp4,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed:
                    () => SubscriptionPaywallSheet.show(
                      context,
                      ref,
                      reason: PaywallReason.quotaExceeded,
                    ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppDimens.touchTarget),
                ),
                child: Text('import_see_plans'.tr()),
              ),
            ),
          ),
        const SizedBox(height: AppDimens.sp24),
        _SectionLabel('statement_import_ways_title'.tr()),
        const SizedBox(height: AppDimens.sp8),
        _Card(
          child: Column(
            children: [
              _FormatRow(
                icon: Icons.description_outlined,
                title: fileTitle,
                body: 'statement_import_way_file_body'.tr(),
                onTap: () => tap(onPick),
              ),
              Divider(height: 1, indent: 64, color: colors.border),
              _FormatRow(
                icon: Icons.screenshot_outlined,
                title: 'statement_import_way_screenshot_title'.tr(),
                body: 'statement_import_way_screenshot_body'.tr(),
                onTap: () => tap(onPickScreenshot),
              ),
              Divider(height: 1, indent: 64, color: colors.border),
              _FormatRow(
                icon: Icons.edit_note_rounded,
                title: 'statement_import_way_write_title'.tr(),
                body: 'statement_import_way_write_body'.tr(),
                onTap: () => tap(onWrite),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimens.sp16),
        _Note(
          icon: Icons.fact_check_outlined,
          text: 'import_intro_point_review'.tr(),
        ),
      ],
      bottom: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: AppDimens.sp4),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: colors.textSecondary,
                ),
              ),
            ),
            TextSpan(text: 'import_intro_point_privacy'.tr()),
          ],
        ),
        textAlign: TextAlign.center,
        style: tt.bodySmall?.copyWith(
          color: colors.textSecondary,
          height: 1.45,
        ),
      ),
    );
  }
}

/// "Escribilo": Porty pide la cartera como le salga ("10 VOO, 2000 dólares
/// en QQQ y algo de NVDA") y después sale la misma vista previa para
/// revisar. Devuelve el texto o `null` si cerró la hoja.
class _NoteSheet extends StatefulWidget {
  const _NoteSheet();

  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const _NoteSheet(),
      );

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final text = _controller.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp8,
        AppDimens.pageHorizontal,
        AppDimens.sp16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortySays(
            messageKey: 'note',
            message: Text('statement_import_note_porty'.tr()),
          ),
          const SizedBox(height: AppDimens.sp16),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: StatementImportClient.maxNoteChars,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'statement_import_note_hint'.tr(),
              counterText: '',
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Text(
            'statement_import_note_cost'.tr(),
            style: tt.bodySmall?.copyWith(
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppDimens.sp16),
          PositionPrimaryButton(
            label: 'statement_import_note_send'.tr(),
            onPressed:
                text.length < 2 ? null : () => Navigator.of(context).pop(text),
          ),
        ],
      ),
    );
  }
}

/// Un formato que sirve: el ícono en su círculo de acento, qué es y cómo
/// lo lee Porty.
class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final row = Padding(
      padding: const EdgeInsets.all(AppDimens.sp16),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.chip,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: colors.onChip),
            ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: tt.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppDimens.sp8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.textSecondary,
              ),
            ],
          ],
        ),
    );
    if (onTap == null) return Semantics(container: true, child: row);
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leyendo: Porty pensando
// ---------------------------------------------------------------------------

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp40),
        child: PortyLoader(
          messageDelay: Duration.zero,
          messages: [
            'import_reading_title'.tr(),
            'statement_import_reading_rows'.tr(),
            'import_reading_body'.tr(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vista previa: lo que encontró, para revisar
// ---------------------------------------------------------------------------

class _Preview extends ConsumerWidget {
  const _Preview({required this.state});

  final StatementImportState state;

  String _warningText(ImportWarning w) => switch (w.type) {
    'skipped_rows' => 'import_warning_skipped'.tr(
      namedArgs: {'count': '${w.count ?? 0}'},
    ),
    'cash_skipped' => 'import_warning_cash'.tr(),
    'ambiguous_dates' => 'import_warning_dates'.tr(),
    'truncated' => 'import_warning_truncated'.tr(
      namedArgs: {'count': '${w.count ?? 0}'},
    ),
    'non_usd_currency' => 'import_warning_currency'.tr(
      namedArgs: {'currencies': w.currencies.join(', ')},
    ),
    _ => '',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final notifier = ref.read(statementImportProvider.notifier);
    final importing = state.phase == ImportPhase.importing;
    final ready = state.ready.length;
    final warnings = [
      for (final w in state.warnings)
        if (_warningText(w).isNotEmpty) _warningText(w),
    ];
    // Contento cuando todo está listo; atento mientras falte algo.
    final mood =
        state.needsAttention == 0 && !state.exceedsLimit
            ? PortyAvatarState.answered
            : PortyAvatarState.serious;

    return _Layout(
      content: [
        PortySays(
          messageKey: 'preview',
          mood: mood,
          message: Text(
            // En tu archivo, en tu captura, en lo que escribiste.
            state.rows.length == 1
                ? 'statement_import_preview_porty_one${_originSuffix(state.origin)}'
                    .tr()
                : 'statement_import_preview_porty${_originSuffix(state.origin)}'
                    .tr(namedArgs: {'count': '${state.rows.length}'}),
          ),
          footnote: Text(
            state.origin != ImportOrigin.file
                ? 'statement_import_preview_note_filled'.tr()
                : state.source == ImportSource.ai
                ? 'statement_import_preview_note_ai'.tr()
                : 'statement_import_preview_note_csv'.tr(),
          ),
        ),
        for (final w in warnings) ...[
          const SizedBox(height: AppDimens.sp12),
          _Note(icon: Icons.info_outline_rounded, text: w),
        ],
        if (state.missingDates > 0 || state.missingPricesFillable > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppDimens.sp16),
            child: Wrap(
              spacing: AppDimens.sp8,
              runSpacing: AppDimens.sp8,
              children: [
                if (state.missingDates > 0)
                  _QuickFix(
                    icon: Icons.today_rounded,
                    label: 'import_fill_dates'.tr(),
                    onTap:
                        importing ? null : notifier.fillMissingDatesWithToday,
                  ),
                if (state.missingPricesFillable > 0)
                  _QuickFix(
                    icon: Icons.sell_outlined,
                    label: 'import_fill_prices'.tr(),
                    onTap:
                        importing
                            ? null
                            : notifier.fillMissingPricesWithCurrent,
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppDimens.sp24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _SectionLabel(
                'statement_import_list_title${_originSuffix(state.origin)}'
                    .tr(),
              ),
            ),
            const SizedBox(width: AppDimens.sp8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                'statement_import_list_ready'.tr(
                  namedArgs: {
                    'ready': '$ready',
                    'count': '${state.included.length}',
                  },
                ),
                textAlign: TextAlign.end,
                style: tt.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp8),
        _Card(
          child: Column(
            children: [
              for (final (i, row) in state.rows.indexed) ...[
                if (i > 0)
                  Divider(height: 1, indent: 100, color: colors.border),
                _RowTile(
                  row: row,
                  alreadyHeld: state.heldTickers.contains(row.ticker),
                  enabled: !importing,
                  onToggle: () => notifier.toggle(row.id),
                  onEdit:
                      () => ImportRowEditSheet.show(
                        context,
                        row: row,
                        onSave:
                            (edit) => notifier.updateRow(
                              row.id,
                              ticker: edit.ticker,
                              quantity: edit.quantity,
                              purchasePrice: edit.purchasePrice,
                              purchaseDate: edit.purchaseDate,
                            ),
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.exceedsLimit) ...[
            _Note(
              icon: Icons.lock_outline_rounded,
              text: 'import_limit_exceeded'.tr(
                namedArgs: {'limit': '${state.positionLimit}'},
              ),
              action: TextButton(
                onPressed:
                    () => SubscriptionPaywallSheet.show(
                      context,
                      ref,
                      reason: PaywallReason.modeLocked,
                    ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppDimens.touchTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.sp4,
                  ),
                ),
                child: Text('import_see_plans'.tr()),
              ),
            ),
            const SizedBox(height: AppDimens.sp12),
          ] else if (state.needsAttention > 0) ...[
            Text(
              (state.needsAttention == 1
                      ? 'import_needs_attention_one'
                      : 'import_needs_attention')
                  .tr(
                namedArgs: {'count': '${state.needsAttention}'},
              ),
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
          ],
          PositionPrimaryButton(
            label:
                state.checkingQuotes
                    ? 'import_checking_tickers'.tr()
                    : ready == 1
                    ? 'import_cta_one'.tr()
                    : 'import_cta'.tr(namedArgs: {'count': '$ready'}),
            loading: importing,
            onPressed: state.canImport ? notifier.importReady : null,
          ),
        ],
      ),
    );
  }
}

/// Un atajo para completar lo que falta en todas a la vez: pastilla
/// tranquila, como las de la app (borde y texto con contraste).
class _QuickFix extends StatelessWidget {
  const _QuickFix({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimens.radiusPill),
      side: BorderSide(color: colors.border),
    );
    return Semantics(
      button: true,
      child: Material(
        color: colors.surfaceCard,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp16,
                vertical: AppDimens.sp8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: AppDimens.iconSm, color: colors.accentBlue),
                  const SizedBox(width: AppDimens.sp8),
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Una posición del archivo: el check para dejarla afuera, el logo, el
/// ticker con su nombre, los datos en una línea y, solo si hace falta,
/// etiquetas chicas con lo que falta. Tocarla abre la corrección.
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.alreadyHeld,
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
  });

  final ImportRow row;
  final bool alreadyHeld;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  static const avatarSize = 36.0;

  List<_Tag> _tags() {
    if (!row.included) {
      return [_Tag('statement_import_tag_excluded'.tr())];
    }
    final issues = row.issues;
    return [
      if (issues.contains(ImportIssue.unknownTicker))
        _Tag('statement_import_tag_ticker'.tr(), warn: true),
      if (issues.contains(ImportIssue.quantity))
        _Tag('statement_import_tag_quantity'.tr(), warn: true),
      if (issues.contains(ImportIssue.price))
        _Tag('statement_import_tag_price'.tr(), warn: true),
      if (issues.contains(ImportIssue.date))
        _Tag('statement_import_tag_date'.tr(), warn: true),
      if (row.hasForeignCurrency)
        _Tag(
          'statement_import_tag_currency'.tr(
            namedArgs: {'currency': row.currency!},
          ),
        ),
      if (row.quantityFromAmount && row.amount != null)
        _Tag(
          'statement_import_tag_from_amount'.tr(
            namedArgs: {'amount': AppNumberFormat.wholeMoney(row.amount!)},
          ),
        ),
      if (alreadyHeld) _Tag('statement_import_tag_held'.tr()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final tags = _tags();
    final details = [
      AppNumberFormat.shares(row.quantity),
      if (row.purchasePrice != null) AppNumberFormat.money(row.purchasePrice!),
      if (row.purchaseDate != null)
        DateFormat.yMMMd().format(row.purchaseDate!),
    ].join(' · ');
    final muted = !row.included;
    final checking = row.included && row.quote == QuoteCheck.pending;

    return InkWell(
      onTap: enabled ? onEdit : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.sp4,
          AppDimens.sp12,
          AppDimens.sp12,
          AppDimens.sp12,
        ),
        child: Row(
          children: [
            Checkbox(
              value: row.included,
              onChanged: enabled ? (_) => onToggle() : null,
              activeColor: colors.accentBlue,
              checkColor: colors.onAccent,
              side: BorderSide(color: colors.textSecondary, width: 1.5),
              semanticLabel: 'import_include_semantics'.tr(
                namedArgs: {'ticker': row.ticker},
              ),
            ),
            AnimatedOpacity(
              opacity: muted ? 0.45 : 1,
              duration: const Duration(milliseconds: 160),
              child: ExcludeSemantics(
                child: QaTickerAvatar(ticker: row.ticker, size: avatarSize),
              ),
            ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Semantics(
                button: enabled,
                hint: 'statement_import_edit_semantics'.tr(
                  namedArgs: {'ticker': row.ticker},
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          flex: 0,
                          child: Text(
                            row.ticker,
                            style: tt.titleSmall?.copyWith(
                              color:
                                  muted
                                      ? colors.textSecondary
                                      : colors.textPrimary,
                              fontWeight: FontWeight.w700,
                              decoration:
                                  muted ? TextDecoration.lineThrough : null,
                              decorationColor: colors.textSecondary,
                            ),
                          ),
                        ),
                        if (row.name != null) ...[
                          const SizedBox(width: AppDimens.sp8),
                          Expanded(
                            child: Text(
                              row.name!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: tt.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: AppDimens.sp8),
                      Wrap(
                        spacing: AppDimens.sp6,
                        runSpacing: AppDimens.sp6,
                        children: tags,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppDimens.sp8),
            if (checking)
              ButtonSpinner.small(color: colors.textSecondary)
            else
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconMd,
                color: colors.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta chica de estado. [warn]: falta algo (tinte terracota y un
/// punto del acento); si no, una aclaración en gris. El texto siempre en
/// tinta, para que se lea en claro y en oscuro.
class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.warn = false});

  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.sp8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color:
            warn
                ? colors.accentBlue.withValues(alpha: 0.14)
                : colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (warn) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.accentBlue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppDimens.sp6),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: warn ? colors.textPrimary : colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Listo
// ---------------------------------------------------------------------------

class _Done extends StatelessWidget {
  const _Done({
    required this.imported,
    required this.importedTickers,
    required this.failed,
    required this.onAnother,
  });

  final int imported;
  final List<String> importedTickers;
  final List<String> failed;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final none = imported == 0;
    var order = 0;
    Widget enter(Widget child) =>
        FadeSlideIn(delay: Duration(milliseconds: 60 * order++), child: child);
    void goHome() {
      PortyHapticsService.maybeOf(context)?.selectionTap();
      context.goNamed(HomeRouter.homeRouteName);
    }

    final secondaryStyle = TextButton.styleFrom(
      foregroundColor: colors.textSecondary,
      minimumSize: const Size(0, AppDimens.touchTarget),
    );

    return _Layout(
      content: [
        const SizedBox(height: AppDimens.sp24),
        enter(
          Center(
            child: ExcludeSemantics(
              child: PortyAvatar(
                size: 72,
                state:
                    none
                        ? PortyAvatarState.concerned
                        : PortyAvatarState.answered,
                animated: true,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp20),
        enter(
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              none
                  ? 'import_done_none'.tr()
                  : imported == 1
                  ? 'import_done_title_one'.tr()
                  : 'import_done_title'.tr(namedArgs: {'count': '$imported'}),
              textAlign: TextAlign.center,
              style: tt.displaySmall?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                height: 1.2,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        enter(
          Text(
            none
                ? 'statement_import_done_none_body'.tr()
                : 'import_done_body'.tr(),
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
        if (importedTickers.isNotEmpty) ...[
          const SizedBox(height: AppDimens.sp24),
          enter(Center(child: _AvatarStack(tickers: importedTickers))),
        ],
        if (failed.isNotEmpty) ...[
          const SizedBox(height: AppDimens.sp24),
          enter(
            _Note(
              icon: Icons.error_outline_rounded,
              text: 'import_done_failed'.tr(
                namedArgs: {'tickers': failed.toSet().join(', ')},
              ),
            ),
          ),
        ],
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (none) ...[
            PositionPrimaryButton(
              label: 'import_another'.tr(),
              onPressed: onAnother,
            ),
            const SizedBox(height: AppDimens.sp4),
            TextButton(
              onPressed: goHome,
              style: secondaryStyle,
              child: Text('import_done_cta'.tr()),
            ),
          ] else ...[
            PositionPrimaryButton(
              label: 'import_done_cta'.tr(),
              onPressed: goHome,
            ),
            const SizedBox(height: AppDimens.sp4),
            TextButton(
              onPressed: onAnother,
              style: secondaryStyle,
              child: Text('import_another'.tr()),
            ),
          ],
        ],
      ),
    );
  }
}

/// Los logos de lo que entró, superpuestos (como una mano de cartas): de
/// un vistazo, "esto ya está en tu cartera". Los que no entran, "+N".
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.tickers});

  final List<String> tickers;

  static const _size = 40.0;
  static const _overlap = 8.0;
  static const _max = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final shown = tickers.take(_max).toList();
    final rest = tickers.length - shown.length;
    final count = shown.length + (rest > 0 ? 1 : 0);
    const step = _size - _overlap;
    // El anillo del color de la superficie separa un logo del otro.
    Widget ring(Widget child) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.background,
        shape: BoxShape.circle,
      ),
      child: child,
    );

    return ExcludeSemantics(
      child: SizedBox(
        width: step * (count - 1) + _size + 4,
        height: _size + 4,
        child: Stack(
          children: [
            for (final (i, t) in shown.indexed)
              Positioned(
                left: step * i,
                child: ring(QaTickerAvatar(ticker: t, size: _size)),
              ),
            if (rest > 0)
              Positioned(
                left: step * shown.length,
                child: ring(
                  Container(
                    width: _size,
                    height: _size,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '+$rest',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas compartidas
// ---------------------------------------------------------------------------

/// Título chico de una sección, sobre su card.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: context.customColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Caja con borde, como las otras cards de la app. Material: las filas
/// pintan el splash adentro.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Material(
      color: colors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Una aclaración en un bloque hundido y gris (sin caja con borde), con
/// una acción opcional debajo.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppDimens.sp12),
      decoration: BoxDecoration(
        color: colors.inset,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: AppDimens.iconSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppDimens.sp8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: tt.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
