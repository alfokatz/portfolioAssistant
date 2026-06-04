import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/managers/environmet_manager.dart';

class EnvironmentManagerImpl extends EnvironmentManager {
  final Ref ref;

  EnvironmentManagerImpl({required this.ref});

  @override
  String getApiUrl() {
    return dotenv.env['API_URL'] as String;
  }
}

final environmentManager = Provider<EnvironmentManager>(
  ((ref) => EnvironmentManagerImpl(ref: ref)),
);
