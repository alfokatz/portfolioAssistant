import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/app_update/app_update_gate.dart';
import 'package:portfolio_assistant/features/app_update/app_update_required_screen.dart';

class _Source implements MinSupportedBuildSource {
  _Source(this.value, {this.fails = false, this.hangs = false});

  final Map<String, dynamic>? value;
  final bool fails;
  final bool hangs;

  @override
  Future<MinSupportedBuild?> fetch(TargetPlatform platform) {
    if (hangs) return Completer<MinSupportedBuild?>().future;
    if (fails) return Future.error(StateError('offline'));
    return SupabaseMinSupportedBuildSource((_) async => value).fetch(platform);
  }
}

Future<AppUpdateStatus> _check(
  MinSupportedBuildSource source, {
  int build = 5,
  TargetPlatform platform = TargetPlatform.iOS,
}) => checkAppUpdate(
  source: source,
  currentBuild: () async => build,
  platform: platform,
  timeout: const Duration(milliseconds: 50),
);

void main() {
  const config = {
    'android': 3,
    'ios': 7,
    'ios_store_url': 'https://apps.apple.com/app/id1',
  };

  test('below the minimum for its platform → update required, with store url', () async {
    final status = await _check(_Source(config));
    expect(status.required, isTrue);
    expect(status.storeUrl, 'https://apps.apple.com/app/id1');
  });

  test('at or above the minimum, or with minimum 0 → no gate', () async {
    expect((await _check(_Source(config), platform: TargetPlatform.android)).required, isFalse);
    expect((await _check(_Source(config), build: 7)).required, isFalse);
    expect((await _check(_Source(const {'ios': 0}))).required, isFalse);
    expect((await _check(_Source(null))).required, isFalse);
  });

  test('fails open: offline or slow config never locks the user out', () async {
    expect((await _check(_Source(config, fails: true))).required, isFalse);
    expect((await _check(_Source(config, hangs: true))).required, isFalse);
  });

  testWidgets('the update screen shows its copy and a single store action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppUpdateRequiredScreen(storeUrl: 'https://store')),
    );
    expect(find.text('app_update_required_title'.tr()), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
