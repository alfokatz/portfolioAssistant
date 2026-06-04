/// Flujos GenUI expuestos en la app (rutas `/genui/{analysis|invest|plan}`).
enum GenUiFlowType {
  analysis,
  invest,
  plan;

  String get routeSuffix => name;
}
