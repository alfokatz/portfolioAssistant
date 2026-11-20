

import 'package:portfolio_assistant/presentation/base/alert/alert_type.dart';

class AlertData {
  final AlertType alertType;
  final String? title;
  final String? message;

  AlertData({required this.alertType, this.title, this.message});
}