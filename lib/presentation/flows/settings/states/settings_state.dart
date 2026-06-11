class SettingsState {
  const SettingsState({
    this.notificationsEnabled = true,
    this.priceAlertsEnabled = true,
    this.isLoading = true,
  });

  final bool notificationsEnabled;
  final bool priceAlertsEnabled;
  final bool isLoading;

  SettingsState copyWith({
    bool? notificationsEnabled,
    bool? priceAlertsEnabled,
    bool? isLoading,
  }) {
    return SettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      priceAlertsEnabled: priceAlertsEnabled ?? this.priceAlertsEnabled,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
