import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/porty_rollout_flag.dart';

void main() {
  test('bucket: the same split as the ai-chat proxy (rolloutBucket)', () {
    // Valores calculados con `rolloutBucket` de supabase/functions/ai-chat.
    expect(PortyRolloutFlag.bucket(''), 61);
    expect(PortyRolloutFlag.bucket('u1'), 35);
    expect(
      PortyRolloutFlag.bucket('3f1c2d9e-8b7a-4c5d-9e0f-1a2b3c4d5e6f'),
      12,
    );
    expect(
      PortyRolloutFlag.bucket('00000000-0000-0000-0000-000000000000'),
      57,
    );
    expect(PortyRolloutFlag.bucket('ñandú'), 65);
  });

  test('users always on; percent splits the rest; anything else off', () {
    const id = '3f1c2d9e-8b7a-4c5d-9e0f-1a2b3c4d5e6f'; // bucket 12
    expect(PortyRolloutFlag.isEnabled(null, id), isFalse);
    expect(PortyRolloutFlag.isEnabled('on', id), isFalse);
    expect(PortyRolloutFlag.isEnabled({'percent': 0}, id), isFalse);
    expect(PortyRolloutFlag.isEnabled({'percent': 12}, id), isFalse);
    expect(PortyRolloutFlag.isEnabled({'percent': 13}, id), isTrue);
    expect(PortyRolloutFlag.isEnabled({'percent': 100}, id), isTrue);
    expect(
      PortyRolloutFlag.isEnabled({
        'percent': 0,
        'users': [id],
      }, id),
      isTrue,
    );
  });

  test('read failures and no user → off, and it reads once per ttl', () async {
    var reads = 0;
    final failing = PortyRolloutFlag(
      'porty_streaming',
      read: () async => throw Exception('offline'),
    );
    expect(await failing.enabledFor('u1'), isFalse);

    final config = PortyRolloutFlag(
      'porty_streaming',
      read: () async {
        reads++;
        return {'percent': 100};
      },
    );
    expect(await config.enabledFor(null), isFalse);
    expect(await config.enabledFor('u1'), isTrue);
    expect(await config.enabledFor('u2'), isTrue);
    expect(reads, 1);
  });
}
