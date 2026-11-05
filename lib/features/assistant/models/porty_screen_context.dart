/// Las pantallas desde donde se puede abrir Porty con contexto.
enum PortyScreen {
  positionDetail('position_detail'),
  closedPosition('closed_position'),
  goals('goals'),
  goalDetail('goal_detail'),
  watchlist('watchlist'),
  allocation('allocation_plan'),
  weeklyReport('weekly_report'),

  /// El primer diagnóstico de la cartera (lo que Porty vio al cargarla).
  diagnosis('portfolio_diagnosis');

  const PortyScreen(this.briefValue);

  /// Cómo viaja en `screen_context.screen` del brief.
  final String briefValue;
}

/// Lo que el usuario estaba mirando cuando abrió Porty: la pantalla y, si
/// es de algo puntual, qué (un ticker, una meta). Viaja en el brief del
/// turno (`screen_context`) para que "¿esto está bien?" o "¿por qué bajó?"
/// se entiendan sin nombrar nada.
class PortyScreenContext {
  const PortyScreenContext(this.screen, {this.ticker, this.goalLabel});

  const PortyScreenContext.position(String ticker)
    : this(PortyScreen.positionDetail, ticker: ticker);

  final PortyScreen screen;
  final String? ticker;

  /// El nombre de la meta, tal como la guardó el usuario.
  final String? goalLabel;

  /// Cuántos turnos sigue valiendo después de abrir el chat: pasado eso, la
  /// conversación ya es sobre otra cosa y "esto" no es la pantalla de antes.
  static const maxTurns = 3;

  /// El bloque `screen_context` del brief. [turnsAgo] = turnos desde que se
  /// abrió el chat desde esa pantalla (0 = la pregunta de ahora).
  Map<String, Object?> toBrief({required int turnsAgo}) => {
    'screen': screen.briefValue,
    if (ticker case final t?) 'ticker': t.toUpperCase(),
    if (goalLabel case final g?) 'goal': g,
    'turns_ago': turnsAgo,
  };
}
