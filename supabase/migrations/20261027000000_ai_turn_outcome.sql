-- Cómo terminó cada turno de Porty, visto desde la app: el proxy `ai-chat`
-- sabe qué rondas pasaron y cuánto costaron, pero no si la respuesta se pudo
-- mostrar (timeout, A2UI ilegible, paywall, sin conexión). Lo reporta la app
-- al terminar el turno, sobre la fila que ya creó el proxy. Ver
-- docs/runbooks/ai-turn-outcomes.md.

alter table public.ai_turn_usage
  add column if not exists outcome text
    check (outcome in ('answered', 'fallback', 'paywall', 'connection_error')),
  -- Código corto (timeout, unreadable, invalid_ui, error…), nunca el texto
  -- de una excepción: puede traer datos de la respuesta.
  add column if not exists outcome_reason text
    check (outcome_reason ~ '^[a-z0-9_]{1,40}$'),
  -- Desde que el usuario mandó la pregunta hasta que vio la respuesta.
  add column if not exists turn_latency_ms int
    check (turn_latency_ms between 0 and 600000),
  -- El chequeo de la respuesta pidió reescribirla (ronda extra).
  add column if not exists answer_rejected boolean,
  -- La respuesta final llegó vacía o rota y se volvió a pedir.
  add column if not exists final_retried boolean,
  add column if not exists outcome_at timestamptz;

create index if not exists ai_turn_usage_outcome_idx
  on public.ai_turn_usage (outcome, created_at);

-- La app reporta el resultado de SU turno, una sola vez. Un turno que no
-- llegó al proxy (sin fila) se ignora. No toca tokens, costo ni cuota: es
-- solo diagnóstico, así que un cliente que mienta solo ensucia sus filas.
create or replace function public.ai_report_turn_outcome(
  p_turn_id text,
  p_outcome text,
  p_reason text default null,
  p_latency_ms int default null,
  p_answer_rejected boolean default null,
  p_final_retried boolean default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  update public.ai_turn_usage
  set outcome = p_outcome,
      outcome_reason = p_reason,
      turn_latency_ms = p_latency_ms,
      answer_rejected = p_answer_rejected,
      final_retried = p_final_retried,
      outcome_at = now()
  where turn_id = p_turn_id
    and user_id = auth.uid()
    and purpose = 'chat'
    and outcome is null;
  return found;
end;
$$;

revoke all on function public.ai_report_turn_outcome(text, text, text, int, boolean, boolean)
  from public, anon;
grant execute on function public.ai_report_turn_outcome(text, text, text, int, boolean, boolean)
  to authenticated, service_role;
