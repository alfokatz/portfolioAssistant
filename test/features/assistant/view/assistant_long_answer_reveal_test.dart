import 'dart:io';
import 'dart:math' as math;

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/investor_profile_repository.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/view/assistant_screen.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_composer_field.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_error_banner.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_quiet_notice.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_header.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/genui_test_helpers.dart';
import '../fakes/assistant_fakes.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

/// Reproduce, sobre la pantalla real, una respuesta larga de Porty (texto +
/// 3 candidatos + disclaimer) entregada como en producción: provider,
/// servicio y loop de tools reales; lo único falso es OpenAI (HTTP guionado)
/// y las fuentes externas.
///
/// Afirma frame a frame lo que el usuario ve: nunca un viewport vacío, la
/// vista anclada al inicio de la respuesta y las cards entrando en orden,
/// con fade + slide.
void main() {
  const previousQuestion = '¿Cómo está mi cartera?';
  const previousAnswer = 'Tu cartera vale 600 dólares hoy.';
  const question = '¿Me recomendás 3 acciones de consumo cíclico?';
  const answerText =
      'Te dejo tres ideas de consumo cíclico para mirar con calma: marcas '
      'globales con demanda estable y buena caja.';
  const tickers = ['NKE', 'MCD', 'SBUX'];

  Widget app(
    _Screen screen, {
    bool reduceMotion = false,
    Widget? home,
    Brightness brightness = Brightness.dark,
  }) {
    return UncontrolledProviderScope(
      container: screen.container,
      child: MaterialApp(
        theme:
            brightness == Brightness.dark
                ? genuiTestTheme()
                : ThemeData(
                  useMaterial3: true,
                  brightness: Brightness.light,
                  scaffoldBackgroundColor: CustomColors.light.background,
                  extensions: [CustomColors.light],
                ),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
        home: home ?? const AssistantScreen(),
      ),
    );
  }

  Future<_Screen> pumpScreen(
    WidgetTester tester, {
    bool reduceMotion = false,
    List<_Step> extraSteps = const [],
  }) async {
    await tester.binding.setSurfaceSize(genuiTestViewportSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final screen = _Screen([
      _answer(previousAnswer),
      _call('get_invest_candidates', {'tickers': tickers}),
      _investAnswer(answerText, tickers),
      ...extraSteps,
    ]);
    addTearDown(screen.dispose);
    await tester.pumpWidget(app(screen, reduceMotion: reduceMotion));
    await tester.pump();
    await tester.pump();
    return screen;
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byType(AssistantSendButton));
    await tester.pump();
  }

  /// Pumpea de a un frame (16 ms) hasta que el turno resolvió, la surface
  /// terminó su reveal y pasó [settle] más; corre [onFrame] en cada frame.
  Future<void> runTurn(
    WidgetTester tester,
    _Screen screen, {
    void Function(int frame)? onFrame,
    Duration settle = const Duration(milliseconds: 800),
  }) async {
    var settledFrames = -1;
    final settleFrames = settle.inMilliseconds ~/ 16;
    for (var frame = 0; frame < 3000; frame++) {
      // `GenUiRequestTracker` hace `await subscription.cancel()` sobre el
      // stream broadcast de genui, que devuelve un future de la zona raíz:
      // FakeAsync no lo drena solo, así que se deja correr un giro real del
      // event loop (sin avanzar el reloj falso) antes de cada frame.
      await tester.runAsync(() async {});
      await tester.pump(const Duration(milliseconds: 16));
      onFrame?.call(frame);
      final state = screen.state;
      final last = state.messages.last;
      final done =
          !state.isWaiting &&
          !last.isStreaming &&
          (last.surfaceId == null || last.hasRevealed);
      if (done && settledFrames < 0) settledFrames = 0;
      if (settledFrames >= 0 && ++settledFrames > settleFrames) return;
    }
    final last = screen.state.messages.last;
    fail(
      'the turn never settled: waiting=${screen.state.isWaiting} '
      'streaming=${last.isStreaming} revealed=${last.hasRevealed} '
      'fallback=${last.isFallback} texts=${_paragraphsInList(tester).map((p) => '${p.text.toPlainText().length > 20 ? p.text.toPlainText().substring(0, 20) : p.text.toPlainText()}@${_effectiveOpacity(p).toStringAsFixed(2)}').toList()}',
    );
  }

  testWidgets('long answer (text + 3 candidates + disclaimer): history never '
      'blanks, the view anchors to the start of the answer and the cards '
      'enter animated and in order', (tester) async {
    final screen = await pumpScreen(tester);

    // Historial previo: un turno ya respondido.
    await send(tester, previousQuestion);
    await runTurn(tester, screen);
    expect(find.text(previousAnswer), findsOneWidget);

    screen.haptics.clear();
    await send(tester, question);

    final blankFrames = <int>[];
    final fullyInFrame = <String, int>{};
    var maxScrollStep = 0.0;
    var maxHeightStep = 0.0;
    double? lastPixels;
    double? lastHeight;
    final questionOutFrames = <int>[];
    var answerSeenWhileTyping = false;
    final firstVisibleFrame = <String, int>{};
    final sawPartialOpacity = <String>{};
    final slideDuringEntrance = <String, double>{};

    await runTurn(
      tester,
      screen,
      onFrame: (frame) {
        final viewport = _chatViewport(tester);

        // (1) Nunca un frame con la lista vacía: siempre hay texto visible.
        if (_visibleTexts(tester, viewport).isEmpty) blankFrames.add(frame);

        // Scroll sin saltos de un frame, y la pregunta siempre visible.
        final pixels = _scrollPixels(tester);
        if (lastPixels != null) {
          maxScrollStep = math.max(maxScrollStep, (pixels - lastPixels!).abs());
        }
        lastPixels = pixels;
        // (Mientras la burbuja del usuario todavía se tipea, su texto no
        // es el final: se cuenta desde que terminó.)
        final asked = _paragraphEqualTo(tester, question);
        if (asked != null && !_isVisible(asked, viewport)) {
          questionOutFrames.add(frame);
        }

        // El alto de la respuesta crece de a poco, no de a una card entera.
        final surface = find.byType(PortfolioQaAssistantSurface).last;
        if (surface.evaluate().isNotEmpty) {
          final height = tester.getSize(surface).height;
          if (lastHeight != null) {
            maxHeightStep = math.max(maxHeightStep, height - lastHeight!);
          }
          lastHeight = height;
        }

        // (2) El texto de Porty se ve MIENTRAS se tipea.
        final typing = _paragraphStartingWith(tester, answerText);
        if (typing != null) {
          final text = typing.text.toPlainText();
          if (text.isNotEmpty &&
              text.length < answerText.length &&
              _isVisible(typing, viewport)) {
            answerSeenWhileTyping = true;
          }
        }

        // (3) Cards: primer frame visible, opacidad intermedia y slide.
        final answer = _paragraphStartingWith(tester, answerText);
        for (final ticker in tickers) {
          final label = _tickerParagraph(tester, ticker);
          if (label == null || answer == null) continue;
          final opacity = _effectiveOpacity(label);
          if (opacity > 0.01) {
            firstVisibleFrame.putIfAbsent(ticker, () => frame);
          }
          if (opacity > 0.99) fullyInFrame.putIfAbsent(ticker, () => frame);
          if (opacity > 0.05 && opacity < 0.95) {
            sawPartialOpacity.add(ticker);
            final relative = _top(label) - _top(answer);
            slideDuringEntrance[ticker] = math.max(
              slideDuringEntrance[ticker] ?? double.negativeInfinity,
              relative,
            );
          }
        }
      },
    );

    expect(
      blankFrames,
      isEmpty,
      reason:
          'the chat viewport showed no visible content in '
          '${blankFrames.length} frames (first: ${blankFrames.firstOrNull})',
    );

    final viewport = _chatViewport(tester);
    final answer = _paragraphStartingWith(tester, answerText);
    expect(answer, isNotNull, reason: 'the answer text left the tree');
    expect(answer!.text.toPlainText(), answerText);
    expect(
      _top(answer),
      inInclusiveRange(viewport.top, viewport.bottom - 20),
      reason: 'the start of Porty\'s answer must stay in the viewport',
    );
    expect(answerSeenWhileTyping, isTrue);

    expect(firstVisibleFrame.keys, containsAll(tickers));
    expect(
      firstVisibleFrame['NKE']! < firstVisibleFrame['MCD']! &&
          firstVisibleFrame['MCD']! < firstVisibleFrame['SBUX']!,
      isTrue,
      reason: 'cards must enter one after the other: $firstVisibleFrame',
    );
    // Solapadas: cada una arranca antes de que la anterior termine.
    expect(firstVisibleFrame['MCD']!, lessThan(fullyInFrame['NKE']!));
    expect(firstVisibleFrame['SBUX']!, lessThan(fullyInFrame['MCD']!));
    expect(sawPartialOpacity, containsAll(tickers), reason: 'fade-in');

    expect(
      questionOutFrames,
      isEmpty,
      reason:
          'the user question left the viewport in ${questionOutFrames.length} '
          'frames (first: ${questionOutFrames.firstOrNull})',
    );
    expect(
      maxScrollStep,
      lessThan(60),
      reason: 'the list must glide (animateTo), not jump in one frame',
    );
    // Antes una card sumaba todo su alto en un frame; ahora ningún frame
    // suma más de una fracción chica de una card (el primer frame de
    // easeOutCubic en 300 ms abre ~15%; dos cards solapadas, algo más).
    final cardHeight =
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('NKE'),
                    matching: find.byType(QaCardShell),
                  )
                  .first,
            )
            .height;
    expect(
      maxHeightStep,
      lessThan(cardHeight * 0.25),
      reason:
          'each card must open its space, not appear at full height '
          '(card: ${cardHeight.toStringAsFixed(0)} px)',
    );

    // Un toque por card al empezar su entrada y el cierre al final.
    expect(screen.revealHaptics, [
      widgetEntryPattern,
      widgetEntryPattern,
      widgetEntryPattern,
      answerCompletePattern,
    ]);
    for (final ticker in tickers) {
      final settled = _top(_tickerParagraph(tester, ticker)!) - _top(answer);
      expect(
        slideDuringEntrance[ticker]! - settled,
        greaterThan(3),
        reason: '$ticker must slide up into place while it fades in',
      );
    }
    expect(find.text('assistant_advice_disclaimer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling an answer out of the list and back does not '
      're-animate nor re-vibrate it', (tester) async {
    const laterTickers = ['HD', 'LOW', 'TGT'];
    final screen = await pumpScreen(
      tester,
      extraSteps: [
        _call('get_invest_candidates', {'tickers': laterTickers}),
        _investAnswer('Otras tres ideas para comparar.', laterTickers),
      ],
    );
    await send(tester, previousQuestion);
    await runTurn(tester, screen);
    await send(tester, question);
    await runTurn(tester, screen);
    await send(tester, 'Dame otras tres');
    await runTurn(tester, screen);

    // Al fondo de todo, la respuesta de NKE/MCD/SBUX queda lejos arriba y
    // el ListView la desmonta.
    final position =
        tester.widget<ListView>(find.byType(ListView)).controller!.position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(_tickerParagraph(tester, 'NKE'), isNull, reason: 'unmounted');

    // Vuelve: se remonta desde el estado (ya revelada).
    screen.haptics.clear();
    position.jumpTo(0);
    final partial = <String>{};
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final ticker in tickers) {
        final label = _tickerParagraph(tester, ticker);
        if (label != null && _effectiveOpacity(label) < 0.99) {
          partial.add(ticker);
        }
      }
    }
    expect(_tickerParagraph(tester, 'NKE'), isNotNull, reason: 'remounted');
    expect(partial, isEmpty, reason: 'already-seen cards must not re-enter');
    expect(_paragraphEqualTo(tester, answerText), isNotNull);
    expect(screen.haptics, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the answer text starts next to Porty; the cards take the '
      'full width, under the avatar', (tester) async {
    final screen = await pumpScreen(tester, reduceMotion: true);
    await send(tester, previousQuestion);
    await runTurn(tester, screen);
    await send(tester, question);
    await runTurn(tester, screen);

    final avatar = tester.getRect(find.byType(PortyAvatar).last);
    final text = _paragraphStartingWith(tester, answerText)!;
    final textLeft = text.localToGlobal(Offset.zero).dx;
    final card = tester.getRect(find.byType(QaCardShell).first);
    expect(textLeft, greaterThan(avatar.right), reason: 'sangría del texto');
    expect(card.left, moreOrLessEquals(avatar.left, epsilon: 1));
    expect(card.top, greaterThan(avatar.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion: no blank frame, everything shows at once and '
      'the view anchors to the start of the answer', (tester) async {
    final screen = await pumpScreen(tester, reduceMotion: true);

    await send(tester, previousQuestion);
    await runTurn(tester, screen);
    screen.haptics.clear();
    await send(tester, question);

    final blankFrames = <int>[];
    final partialOpacity = <String>{};
    await runTurn(
      tester,
      screen,
      onFrame: (frame) {
        final viewport = _chatViewport(tester);
        if (_visibleTexts(tester, viewport).isEmpty) blankFrames.add(frame);
        for (final ticker in tickers) {
          final label = _tickerParagraph(tester, ticker);
          if (label == null) continue;
          final opacity = _effectiveOpacity(label);
          if (opacity > 0.05 && opacity < 0.95) partialOpacity.add(ticker);
        }
      },
    );

    expect(blankFrames, isEmpty);
    expect(partialOpacity, isEmpty, reason: 'no fades under reduce motion');
    expect(
      _isVisible(_paragraphEqualTo(tester, question)!, _chatViewport(tester)),
      isTrue,
    );
    // Sin toques por widget: solo el cierre de "respuesta lista".
    expect(screen.revealHaptics.last, answerCompletePattern);
    expect(screen.revealHaptics, isNot(contains(widgetEntryPattern)));
    final answer = _paragraphStartingWith(tester, answerText)!;
    expect(answer.text.toPlainText(), answerText);
    final viewport = _chatViewport(tester);
    expect(_top(answer), inInclusiveRange(viewport.top, viewport.bottom - 20));
    expect(tester.takeException(), isNull);
  });

  group('message avatar', () {
    /// Recorre un turno guardando, por frame, lo que pinta el avatar del
    /// mensaje en curso (si ya está en pantalla), su caja en coordenadas del
    /// contenido de la lista (sin el scroll) y lo que pinta el del header.
    Future<
      ({
        List<PortyFrame> frames,
        Set<Rect> boxes,
        Set<PortyAvatarState> header,
      })
    >
    recordTurn(WidgetTester tester, _Screen screen, String text) async {
      final frames = <PortyFrame>[];
      final boxes = <Rect>{};
      final header = <PortyAvatarState>{};
      void record() {
        header.add(_headerAvatar(tester).state);
        final avatar = _turnAvatar(tester);
        if (avatar == null) return;
        frames.add(_frameOf(tester, avatar));
        boxes.add(
          tester.getRect(avatar).translate(0, _scrollPixels(tester)),
        );
      }

      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.tap(find.byType(AssistantSendButton));
      await tester.pump();
      record();
      // Como runTurn, pero el turno también cierra con un aviso, un error o
      // la fila quitada (que nunca terminan un reveal).
      var settled = -1;
      for (var frame = 0; frame < 3000 && settled < 50; frame++) {
        await tester.runAsync(() async {});
        await tester.pump(const Duration(milliseconds: 16));
        record();
        final state = screen.state;
        final last = state.messages.last;
        final closed =
            !state.isWaiting &&
            !last.isStreaming &&
            (last.surfaceId == null ||
                last.notice != null ||
                last.hasRevealed ||
                state.error != null);
        if (closed || settled >= 0) settled++;
      }
      // La sonrisa dura 3 s y vuelve a reposo.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        record();
      }
      return (frames: frames, boxes: boxes, header: header);
    }

    List<PortyAvatarState> statesOf(List<PortyFrame> frames) {
      final seen = <PortyAvatarState>[];
      for (final f in frames) {
        if (seen.isEmpty || seen.last != f.state) seen.add(f.state);
      }
      return seen;
    }

    // Lo mismo en tema claro y oscuro.
    for (final brightness in Brightness.values) {
    testWidgets('[${brightness.name}] one turn: the message avatar thinks (chat pulse) → answers '
        '→ smiles and keeps the smile, still, in the same place and box; the '
        'header avatar stays idle', (tester) async {
      // La respuesta tarda 1,5 s: Porty llega a pensar, con cualquier carga.
      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final screen = _Screen([
        _answer(previousAnswer),
      ], responseDelay: const Duration(milliseconds: 1500));
      addTearDown(screen.dispose);
      await tester.pumpWidget(app(screen, brightness: brightness));
      await tester.pump();
      await tester.pump();
      final turn = await recordTurn(tester, screen, previousQuestion);
      expect(statesOf(turn.frames), [
        PortyAvatarState.thinking,
        PortyAvatarState.answering,
        PortyAvatarState.answered,
      ]);
      // Sin saltos: misma posición y tamaño de caja de punta a punta.
      expect(turn.boxes, hasLength(1));
      expect(turn.boxes.single.size, const Size.square(36));
      // Un solo Porty actuando: el del header no pasa por ningún estado.
      expect(turn.header, {PortyAvatarState.idle});

      final thinking = turn.frames.where(
        (f) => f.state == PortyAvatarState.thinking && f.from == null,
      );
      // El pulso del orbe sobre el cuerpo, el eco y sin destello.
      expect(thinking.map((f) => f.scale).toSet().length, greaterThan(1));
      expect(
        thinking.every((f) => f.scale >= 0.86 && f.scale <= 1.08),
        isTrue,
      );
      expect(thinking.any((f) => f.echoOpacity > 0.05), isTrue);
      expect(thinking.any((f) => f.haloOpacity > 0.5), isTrue);
      expect(thinking.map((f) => f.dy).toSet().length, greaterThan(1));
      expect(
        turn.frames.any((f) => f.visibleParts.contains(PortyPart.spark)),
        isFalse,
      );
      // Antes de hablar, el pulso se asentó en escala 1 y el eco se apagó.
      final firstAnswering = turn.frames.firstWhere(
        (f) => f.state == PortyAvatarState.answering,
      );
      expect(firstAnswering.scale, closeTo(1, 0.02));
      expect(firstAnswering.echoOpacity, 0);

      // Al final, sonriendo y quieto, como el resto del historial.
      expect(
        turn.frames.last,
        const PortyFrame.still(PortyAvatarState.answered, spark: false),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('[${brightness.name}] a bad-news answer ends barely sad '
        '(concerned), not smiling', (
      tester,
    ) async {
      const badNews = 'Tu cartera bajó 3,2 % esta semana, sobre todo por NVDA.';
      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final screen = _Screen([
        _answer(badNews),
      ], responseDelay: const Duration(milliseconds: 1500));
      addTearDown(screen.dispose);
      await tester.pumpWidget(app(screen, brightness: brightness));
      await tester.pump();
      await tester.pump();

      final turn = await recordTurn(tester, screen, previousQuestion);
      expect(statesOf(turn.frames), [
        PortyAvatarState.thinking,
        PortyAvatarState.answering,
        PortyAvatarState.concerned,
      ]);
      expect(
        turn.frames.last,
        const PortyFrame.still(PortyAvatarState.concerned, spark: false),
      );
      expect(turn.header, {PortyAvatarState.idle});
    });
    }

    testWidgets('the daily limit notice replaces the wait next to the same '
        'avatar, which turns to error', (tester) async {
      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final screen = _Screen([(_) => proxyRejection(429, 'daily_limit')]);
      addTearDown(screen.dispose);
      await tester.pumpWidget(app(screen));
      await tester.pump();
      await tester.pump();

      final turn = await recordTurn(tester, screen, previousQuestion);
      expect(find.byType(AssistantQuietNotice), findsOneWidget);
      // Según cuánto tarde el rechazo, la fila aparece pensando o ya en
      // error (si llega antes de que se termine de tipear la pregunta).
      final states = statesOf(turn.frames);
      expect(states.last, PortyAvatarState.error);
      expect(
        states,
        anyOf([
          [PortyAvatarState.thinking, PortyAvatarState.error],
          [PortyAvatarState.error],
        ]),
      );
      expect(turn.boxes, hasLength(1));
      expect(turn.header, {PortyAvatarState.idle});
    });

    testWidgets('a connection error takes the whole row (avatar included) '
        'and shows the banner', (tester) async {
      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final screen = _Screen([(_) => throw const SocketException('offline')]);
      addTearDown(screen.dispose);
      await tester.pumpWidget(app(screen));
      await tester.pump();
      await tester.pump();

      final turn = await recordTurn(tester, screen, previousQuestion);
      // Si la fila llegó a verse, fue pensando; después se va entera.
      expect(
        turn.frames.every((f) => f.state == PortyAvatarState.thinking),
        isTrue,
      );
      expect(_turnAvatar(tester), isNull);
      expect(find.byType(AssistantErrorBanner), findsOneWidget);
      expect(turn.header, {PortyAvatarState.idle});
    });

    testWidgets('with reduce motion: no pulse, no echo, no movement; only '
        'the expression changes', (tester) async {
      final screen = await pumpScreen(tester, reduceMotion: true);
      final turn = await recordTurn(tester, screen, previousQuestion);
      final states = turn.frames.map((f) => f.state).toSet();
      expect(states, contains(PortyAvatarState.thinking));
      expect(states, contains(PortyAvatarState.answered));
      for (final frame in turn.frames) {
        expect(frame, PortyFrame.still(frame.state, spark: false));
      }
    });
  });
}

// ------------------------------------------------------------ render helpers

double _scrollPixels(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!.position.pixels;

RenderParagraph? _paragraphEqualTo(WidgetTester tester, String text) {
  for (final p in _paragraphsInList(tester)) {
    if (p.text.toPlainText() == text) return p;
  }
  return null;
}

/// Zona del chat que el usuario ve: el `ListView`, sin la franja que tapa el
/// composer flotante.
Rect _chatViewport(WidgetTester tester) {
  final list = tester.getRect(find.byType(ListView));
  final composerTop = tester.getRect(find.byType(AssistantComposerField)).top;
  return Rect.fromLTRB(list.left, list.top, list.right, composerTop);
}

Iterable<RenderParagraph> _paragraphsInList(WidgetTester tester) =>
    tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(RichText),
      ),
    );

List<RenderParagraph> _visibleTexts(WidgetTester tester, Rect viewport) => [
  for (final p in _paragraphsInList(tester))
    if (p.text.toPlainText().trim().isNotEmpty && _isVisible(p, viewport)) p,
];

bool _isVisible(RenderBox box, Rect viewport) {
  if (!box.attached || !box.hasSize) return false;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final overlap = rect.intersect(viewport);
  return overlap.height > 4 &&
      overlap.width > 4 &&
      _effectiveOpacity(box) > 0.05;
}

/// Opacidad acumulada desde [box] hasta el viewport del scroll.
double _effectiveOpacity(RenderObject box) {
  var opacity = 1.0;
  RenderObject? node = box;
  while (node != null && node is! RenderViewportBase) {
    if (node is RenderOpacity) opacity *= node.opacity;
    if (node is RenderAnimatedOpacity) opacity *= node.opacity.value;
    node = node.parent;
  }
  return opacity;
}

double _top(RenderBox box) => box.localToGlobal(Offset.zero).dy;

RenderParagraph? _paragraphStartingWith(WidgetTester tester, String full) {
  for (final p in _paragraphsInList(tester)) {
    final text = p.text.toPlainText();
    if (text.length >= 12 && full.startsWith(text)) return p;
    if (text.isNotEmpty && text.length < 12 && full.startsWith(text)) {
      return p;
    }
  }
  return null;
}

RenderParagraph? _tickerParagraph(WidgetTester tester, String ticker) {
  for (final p in _paragraphsInList(tester)) {
    if (p.text.toPlainText() == ticker) return p;
  }
  return null;
}

// ------------------------------------------------------------------ harness

PortyFrame _frameOf(WidgetTester tester, Finder avatar) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: avatar, matching: find.byType(CustomPaint)),
  );
  return (paint.painter! as PortyAvatarPainter).frame;
}

/// El avatar del turno en curso: el último de la lista, si hay más que el
/// del saludo.
Finder? _turnAvatar(WidgetTester tester) {
  final inList = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(PortyAvatar),
  );
  if (inList.evaluate().length < 2) return null;
  return inList.last;
}

/// Lo que pinta el avatar del header en este frame.
PortyFrame _headerAvatar(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.descendant(
        of: find.byType(PortyHeader),
        matching: find.byType(PortyAvatar),
      ),
      matching: find.byType(CustomPaint),
    ),
  );
  return (paint.painter! as PortyAvatarPainter).frame;
}

typedef _Step = Map<String, Object?> Function(Map<String, dynamic>);

String _surfaceIdOf(Map<String, dynamic> body) {
  final messages = (body['messages'] as List).cast<Map>();
  final lastUser = messages.lastWhere((m) => m['role'] == 'user');
  final content = (lastUser['content'] as List).first['text'] as String;
  return RegExp(r'SURFACE_ID[^:]*: (\S+)').firstMatch(content)!.group(1)!;
}

_Step _answer(String text) =>
    (body) => textReply(a2uiAnswer(_surfaceIdOf(body), text));

_Step _call(String name, Map<String, Object?> args) =>
    (_) => toolCallsReply([('call_1', name, args)]);

/// Respuesta final como la del modelo en producción: texto + una
/// `QaInvestOption` por candidato, en un solo A2UI.
_Step _investAnswer(String text, List<String> tickers) => (body) {
  final id = _surfaceIdOf(body);
  final cards = [
    for (final (i, t) in tickers.indexed)
      '{"id":"c$i","component":"QaInvestOption","ticker":"$t",'
          '"thesis":"Marca global con poder de precio y caja estable.",'
          '"fitScore":${70 + i},"pro":"Demanda resiliente",'
          '"con":"Sensible al ciclo de consumo","currentPrice":150,'
          '"riskLevel":"intermedio","sector":"Consumo cíclico"}',
  ];
  final children = ['"t"', for (var i = 0; i < tickers.length; i++) '"c$i"'];
  return textReply(
    '{"version":"v0.9","createSurface":{"surfaceId":"$id",'
    '"catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
    '{"version":"v0.9","updateComponents":{"surfaceId":"$id","components":['
    '{"id":"root","component":"Column","children":[${children.join(',')}]},'
    '{"id":"t","component":"QaAnswerText","text":"$text"},'
    '${cards.join(',')}]}}',
  );
};

class _Screen {
  _Screen(List<_Step> script, {Duration responseDelay = Duration.zero})
    : api = ScriptedOpenAi(script, responseDelay: responseDelay),
      _subscriptions = _FakeSubscriptionRepository() {
    final tracker = AiUsageTracker(repository: _subscriptions);
    container = ProviderContainer(
      overrides: [
        homeProvider.overrideWith((ref) => _LoadedHome(ref)),
        getClosedPositionsUseCaseProvider.overrideWithValue(
          _NoClosedPositions(),
        ),
        aiUsageTrackerProvider.overrideWithValue(tracker),
        revenueCatServiceProvider.overrideWithValue(_UnusedRevenueCat()),
        subscriptionProvider.overrideWith(
          (ref) => SubscriptionNotifier(
            tracker: tracker,
            authService: _Session(),
            revenueCat: _UnusedRevenueCat(),
          ),
        ),
        investorProfileProvider.overrideWith(
          (ref) => InvestorProfileNotifier(
            repository: _FreshProfileRepository(),
            authService: _Session(),
          ),
        ),
        portyHapticsServiceProvider.overrideWithValue(
          PortyHapticsService(
            enabled: true,
            performer: (pattern) async => haptics.add(pattern),
          ),
        ),
        companyBrandLoaderProvider.overrideWithValue(
          CompanyBrandLoader(_NoBrands()),
        ),
        assistantDepsProvider.overrideWithValue(
          AssistantDeps(
            createService:
                () => AssistantOpenAiService(
                  proxy: AiProxyConfig.fixed(Uri.parse('https://proxy.test'), 'jwt-test'),
                  model: 'gpt-4.1-mini',
                  httpClient: api.client,
                ),
            createData: () => fakeDataSources(),
          ),
        ),
      ],
    );
  }

  final ScriptedOpenAi api;
  final _FakeSubscriptionRepository _subscriptions;
  late final ProviderContainer container;

  /// Cada vibración que pidió la app, en orden.
  final haptics = <PortyHapticPattern>[];

  /// Vibraciones de la respuesta en sí (sin los ticks del typewriter).
  List<PortyHapticPattern> get revealHaptics =>
      haptics.where((p) => p != streamTickPattern).toList();

  ProviderElementBase<Object?> get _element => container
      .getAllProviderElements()
      .firstWhere((e) => e.origin.from == assistantProvider);

  /// Mantiene vivo el provider (es autoDispose) aunque la pantalla se
  /// desmonte — como el tab del asistente en el shell de la app.
  void keepAlive() => container.listen<Object?>(_element.origin, (_, _) {});

  /// El estado del provider que montó la pantalla (su `AssistantArgs` no
  /// es `const`, así que se busca por familia en vez de leer uno nuevo).
  AssistantState get state => _element.readSelf() as AssistantState;

  void dispose() => container.dispose();
}

class _FakeSubscriptionRepository implements SubscriptionRepository {
  var _used = 260;

  @override
  Future<SubscriptionStatus> fetchStatus() async => SubscriptionStatus(
    tier: SubscriptionTier.gold,
    queriesUsed: _used,
    queriesLimit: 1000,
    month: '2026-09',
  );

  @override
  Future<bool> consumeQuota(int weight) async {
    _used += weight;
    return true;
  }
}

class _NoBrands implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async => null;
}

class _Session implements SupabaseAuthService {
  @override
  Session? get currentSession => Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: const User(
      id: 'user',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

class _UnusedRevenueCat extends _Unused implements RevenueCatService {}

class _UnusedSummaryUseCase extends _Unused
    implements GetPortfolioSummaryUseCase {}

class _UnusedHistoryUseCase extends _Unused
    implements GetPortfolioHistoryUseCase {}

class _UnusedBenchmarkUseCase extends _Unused
    implements GetBenchmarkComparisonUseCase {}

class _UnusedDeleteUseCase extends _Unused
    implements DeletePositionsByTickerUseCase {}

class _UnusedClosedRepository extends _Unused
    implements ClosedPositionRepository {}

/// Perfil vigente: la respuesta lleva solo el disclaimer, sin el aviso de
/// completar perfil (que acá, sin traducciones cargadas, desborda).
class _FreshProfileRepository extends _Unused
    implements InvestorProfileRepository {
  @override
  Future<InvestorProfile?> fetch() async => InvestorProfile(
    risk: RiskTolerance.moderate,
    horizon: InvestmentHorizon.long,
    objective: InvestmentObjective.growth,
    updatedAt: DateTime.now(),
  );
}

class _NoClosedPositions extends GetClosedPositionsUseCase {
  _NoClosedPositions() : super(repository: _UnusedClosedRepository());

  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) async =>
      const Right([]);
}

class _LoadedHome extends HomeProvider {
  _LoadedHome(Ref ref)
    : super(
        ref: ref,
        getPortfolioSummaryUseCase: _UnusedSummaryUseCase(),
        getPortfolioHistoryUseCase: _UnusedHistoryUseCase(),
        getBenchmarkComparisonUseCase: _UnusedBenchmarkUseCase(),
        deletePositionsByTickerUseCase: _UnusedDeleteUseCase(),
        getClosedPositionsUseCase: _NoClosedPositions(),
      ) {
    state = HomeState(summary: heldSummary);
  }
}
