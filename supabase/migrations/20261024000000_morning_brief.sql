-- Resumen de la mañana (fase 2 de docs/superpowers/plans/2026-10-24-porty-en-toda-la-app.md):
-- `morning_brief`, a las 8 de la hora local, solo si Porty ve algo nuevo en
-- la cartera (concentración, desvío del plan). Automático: cuenta para el
-- tope diario. Preferencia propia, prendida por defecto.

alter table public.notification_preferences
  add column if not exists morning_brief boolean not null default true;

alter table public.notification_outbox
  drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox
  add constraint notification_outbox_kind_check check (kind in (
    'test', 'price_alert', 'big_move', 'big_move_digest', 'portfolio_move',
    'weekly_report', 'etoro_reconnect', 'earnings_tomorrow', 'earnings_result',
    'allocation_drift', 'watchlist_move', 'morning_brief'
  ));

-- Igual que en 20261016000100_push_new_kinds.sql, con la preferencia nueva
-- en los defaults y el tipo nuevo en el tope diario.
create or replace function public.push_dispatch_context(p_user_ids uuid[])
returns table (
  user_id uuid,
  tier text,
  prefs jsonb,
  devices jsonb,
  automatic_last_24h int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.id,
    coalesce(public._effective_tier(u.id), 'free'),
    coalesce(
      (select to_jsonb(p) - 'user_id' - 'updated_at'
         from public.notification_preferences p where p.user_id = u.id),
      jsonb_build_object(
        'enabled', true, 'price_alerts', true, 'big_moves', true,
        'portfolio_moves', true, 'weekly_report', true, 'earnings', true,
        'service', true, 'morning_brief', true,
        'big_move_sensitivity', 'normal',
        'quiet_start', '22:00:00', 'quiet_end', '08:00:00',
        'show_amounts', false)
    ),
    coalesce(
      (select jsonb_agg(jsonb_build_object(
                'id', d.id, 'token', d.token, 'platform', d.platform,
                'locale', d.locale, 'timezone', d.timezone)
              order by d.last_seen_at desc)
         from public.push_devices d where d.user_id = u.id),
      '[]'::jsonb
    ),
    (select count(*)::int from public.notification_log l
      where l.user_id = u.id
        and l.sent_at > now() - interval '24 hours'
        and l.kind in ('big_move', 'big_move_digest', 'portfolio_move',
                       'weekly_report', 'earnings_tomorrow', 'earnings_result',
                       'allocation_drift', 'watchlist_move',
                       'morning_brief'))
  from auth.users u
  where u.id = any (p_user_ids);
$$;

revoke all on function public.push_dispatch_context(uuid[]) from public, anon, authenticated;
grant execute on function public.push_dispatch_context(uuid[]) to service_role;
