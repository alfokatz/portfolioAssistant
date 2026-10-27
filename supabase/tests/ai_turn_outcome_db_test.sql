-- Test de la migración 20261027000000_ai_turn_outcome.sql (cómo terminó
-- cada turno de Porty, reportado por la app).
--
-- Corre contra una base con las migraciones aplicadas (supabase start).
-- Cada chequeo que falla corta con una excepción; si termina, imprime
-- AI_TURN_OUTCOME_DB_TEST_OK.
--
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/ai_turn_outcome_db_test.sql
--
-- Todo corre dentro de una transacción que se deshace al final.

begin;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'a@test.porty'),
  ('00000000-0000-0000-0000-0000000000b2', 'b@test.porty');

-- Las filas las crea el proxy (service role) al empezar cada turno.
insert into public.ai_turn_usage (turn_id, user_id, tier, model, purpose) values
  ('turn_a_chat_1', '00000000-0000-0000-0000-0000000000a1', 'free', 'gpt-6-luna', 'chat'),
  ('turn_a_chat_2', '00000000-0000-0000-0000-0000000000a1', 'free', 'gpt-6-luna', 'chat'),
  ('turn_a_report', '00000000-0000-0000-0000-0000000000a1', 'free', 'gpt-6-luna', 'weekly_report'),
  ('turn_b_chat_1', '00000000-0000-0000-0000-0000000000b2', 'free', 'gpt-6-luna', 'chat');

-- ── Sin sesión no se puede reportar ───────────────────────────────────────
set local role anon;
do $$
begin
  begin
    perform public.ai_report_turn_outcome('turn_a_chat_1', 'answered');
    raise exception 'anon pudo llamar ai_report_turn_outcome';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ── El usuario A reporta sus turnos ───────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

do $$
begin
  if not public.ai_report_turn_outcome(
    'turn_a_chat_1', 'fallback', 'timeout', 25000, true, false
  ) then
    raise exception 'no se guardó el resultado de un turno propio';
  end if;

  -- Una sola vez: un segundo reporte no pisa el primero.
  if public.ai_report_turn_outcome('turn_a_chat_1', 'answered') then
    raise exception 'un segundo reporte pisó el primero';
  end if;

  -- Turno de otro usuario, del informe semanal o inexistente: se ignora.
  if public.ai_report_turn_outcome('turn_b_chat_1', 'answered') then
    raise exception 'A pudo reportar un turno de B';
  end if;
  if public.ai_report_turn_outcome('turn_a_report', 'answered') then
    raise exception 'se reportó un turno del informe semanal';
  end if;
  if public.ai_report_turn_outcome('turn_no_existe', 'answered') then
    raise exception 'se reportó un turno que no existe';
  end if;

  -- Valores fuera de lo permitido: los rechaza el check.
  begin
    perform public.ai_report_turn_outcome('turn_a_chat_2', 'hacked');
    raise exception 'aceptó un outcome inválido';
  exception when check_violation then null;
  end;
  begin
    perform public.ai_report_turn_outcome(
      'turn_a_chat_2', 'fallback', 'Bad Request: {"x": "datos"}'
    );
    raise exception 'aceptó un reason que no es un código corto';
  exception when check_violation then null;
  end;
end $$;

-- No puede tocar las columnas a mano: solo por la RPC.
do $$
begin
  update public.ai_turn_usage set cost_usd = 0, outcome = 'answered'
  where turn_id = 'turn_a_chat_2';
  if found then
    raise exception 'el usuario pudo editar ai_turn_usage directo';
  end if;
exception when insufficient_privilege then
  null; -- sin grant de update: también vale
end $$;

reset role;

do $$
declare
  r public.ai_turn_usage%rowtype;
begin
  select * into r from public.ai_turn_usage where turn_id = 'turn_a_chat_1';
  if r.outcome <> 'fallback' or r.outcome_reason <> 'timeout'
     or r.turn_latency_ms <> 25000 or not r.answer_rejected
     or r.final_retried or r.outcome_at is null then
    raise exception 'resultado guardado mal: %', row_to_json(r);
  end if;
  if exists (
    select 1 from public.ai_turn_usage
    where turn_id in ('turn_a_chat_2', 'turn_a_report', 'turn_b_chat_1')
      and outcome is not null
  ) then
    raise exception 'se marcó un turno que no correspondía';
  end if;
end $$;

select 'AI_TURN_OUTCOME_DB_TEST_OK' as result;

rollback;
