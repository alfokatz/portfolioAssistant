import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';

/// Nombre de pila para el saludo de la Home (el `full_name` de la cuenta,
/// el mismo que se edita en Ajustes), o `null` si no hay. Se recalcula con
/// cada evento de auth, así un cambio de nombre llega sin recargar.
/// Sin Supabase (tests) también es `null`.
final homeFirstNameProvider = Provider<String?>((ref) {
  try {
    ref.watch(authSessionProvider);
    final fullName =
        ref
            .read(supabaseAuthServiceProvider)
            .currentUser
            ?.userMetadata?['full_name'];
    if (fullName is! String) return null;
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? null : first;
  } catch (_) {
    return null;
  }
});
