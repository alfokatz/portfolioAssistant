-- eToro: la primera importación es gratis (docs/superpowers/plans/
-- 2026-10-26-aha-moment.md, fase 2).
--
-- Un usuario Free puede conectar eToro una vez: el callback importa la
-- cartera y en el acto la deja como posiciones manuales y borra los tokens
-- (no se guardan tokens de usuarios Free). `free_import_at` marca que ya la
-- usó; la sincronización automática sigue siendo de Premium.

alter table public.etoro_connections
  add column if not exists free_import_at timestamptz;

-- Cierra una importación gratis que salió bien: lo importado pasa a manual
-- (como `etoro_disconnect(..., true)`), se borran tokens y estados OAuth y
-- la conexión queda desconectada, pero conserva `last_result` para la
-- pantalla de resultado.
create or replace function public.etoro_finish_free_import(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_open int;
  v_closed int;
begin
  update public.positions
  set source = 'manual', external_id = null, synced_at = null, broker_price = null
  where user_id = p_user_id and source = 'etoro';
  get diagnostics v_open = row_count;
  update public.closed_positions
  set source = 'manual', external_id = null, synced_at = null
  where user_id = p_user_id and source = 'etoro';
  get diagnostics v_closed = row_count;

  perform public.etoro_tokens_delete(p_user_id);
  delete from public.etoro_oauth_states where user_id = p_user_id;

  update public.etoro_connections set
    status = 'disconnected',
    granted_scopes = '{}',
    last_error_type = null,
    history_synced_until = null,
    sync_lock_until = null,
    free_import_at = now(),
    updated_at = now()
  where user_id = p_user_id;

  return jsonb_build_object('open', v_open, 'closed', v_closed);
end;
$$;

revoke all on function public.etoro_finish_free_import(uuid)
  from public, anon, authenticated;
grant execute on function public.etoro_finish_free_import(uuid) to service_role;
