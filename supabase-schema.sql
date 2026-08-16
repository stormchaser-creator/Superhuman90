-- SH90 Supabase Schema
-- Run this in Supabase Dashboard → SQL Editor
--
-- Security model (since v3.2):
--   · Every device signs in with Supabase anonymous auth (no login UI — the app
--     calls signInAnonymously() on first launch and persists the session).
--   · Every table carries user_id UUID DEFAULT auth.uid(); RLS restricts all
--     access to user_id = auth.uid(). The anon key alone grants NOTHING.
--   · The device_id (random 128-bit UUID in localStorage) stays the durable
--     identity anchor: sh90_claim_device() stamps user_id = auth.uid() on all
--     rows of a device_id. The app claims on every launch/resume, so a lost
--     auth session or a linked second device (?device= URL) self-heals by
--     re-claiming. Knowledge of a device_id is the bearer credential for a
--     claim — the same trust model as the ?device= link feature.
--   · Requires "Allow anonymous sign-ins" enabled in Auth settings.
--   · The nightly maintenance agent must use the service_role key (or the
--     Management API) — the anon role has no table access at all.

-- Tables
CREATE TABLE IF NOT EXISTS devices (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT UNIQUE NOT NULL, user_id UUID DEFAULT auth.uid(), created_at TIMESTAMPTZ DEFAULT now());

CREATE TABLE IF NOT EXISTS profiles (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT UNIQUE NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), name TEXT DEFAULT '', age TEXT DEFAULT '', height TEXT DEFAULT '', goal_weight TEXT DEFAULT '', notes TEXT DEFAULT '', theme TEXT DEFAULT 'arctic', text_size TEXT DEFAULT 'medium', workout_mode TEXT DEFAULT 'gym', calorie_goal INT DEFAULT 2000, next_workout_week INT DEFAULT 1, next_workout_day INT DEFAULT 1, rounds JSONB, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now());

CREATE TABLE IF NOT EXISTS exercise_logs (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, exercise_name TEXT NOT NULL, set_index INT NOT NULL, weight TEXT, reps TEXT, done BOOLEAN DEFAULT false, completed_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date, exercise_name, set_index));

CREATE TABLE IF NOT EXISTS sessions (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, week INT NOT NULL, day INT NOT NULL, status TEXT DEFAULT 'active', routine TEXT DEFAULT 'sh90', label TEXT, started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

-- ── Support tickets (CredentialDOMD pattern, device-keyed) ──────────────────
CREATE TABLE IF NOT EXISTS support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  user_id UUID DEFAULT auth.uid(),
  subject TEXT NOT NULL,
  body TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'other' CHECK (category IN ('bug','feature_request','data_issue','question','other')),
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  status TEXT DEFAULT 'open' CHECK (status IN ('open','in_progress','waiting_user','resolved','closed')),
  context_page TEXT,
  app_version TEXT,
  resolution_note TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  resolved_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  user_id UUID DEFAULT auth.uid(), -- NULL for agent-authored rows (service role)
  author TEXT NOT NULL DEFAULT 'user', -- 'user' | 'agent'
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sh90_tickets_status  ON support_tickets (status, priority, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sh90_messages_ticket ON support_messages (ticket_id, created_at);

CREATE TABLE IF NOT EXISTS weight_log (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, weight DECIMAL NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

CREATE TABLE IF NOT EXISTS habit_log (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, h0 BOOLEAN DEFAULT false, h1 BOOLEAN DEFAULT false, h2 BOOLEAN DEFAULT false, h3 BOOLEAN DEFAULT false, h4 BOOLEAN DEFAULT false, h5 BOOLEAN DEFAULT false, h6 BOOLEAN DEFAULT false, h7 BOOLEAN DEFAULT false, h8 BOOLEAN DEFAULT false, h9 BOOLEAN DEFAULT false, h10 BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));
-- h8 (Studying) + h9 (Sleep 9h+) + h10 (Chores) added 2026-08-15 for the Buff TXN teen habit set (APPLIED to live DB)

CREATE TABLE IF NOT EXISTS habit_notes (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, habit_index INT NOT NULL, note TEXT DEFAULT '', created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date, habit_index));

CREATE TABLE IF NOT EXISTS step_log (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, steps INT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

CREATE TABLE IF NOT EXISTS food_entries (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, entry_id BIGINT NOT NULL, food_text TEXT NOT NULL, category TEXT DEFAULT '', logged_at TEXT, items JSONB DEFAULT '[]', calories INT DEFAULT 0, protein INT DEFAULT 0, carbs INT DEFAULT 0, fat INT DEFAULT 0, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, entry_id));

CREATE TABLE IF NOT EXISTS exercise_swaps (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), week INT NOT NULL, day INT NOT NULL, original_exercise TEXT NOT NULL, swapped_exercise TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, week, day, original_exercise));

CREATE TABLE IF NOT EXISTS workout_selection (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), user_id UUID DEFAULT auth.uid(), date DATE NOT NULL, day INT NOT NULL, label TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

-- Claim: an authenticated (anonymous) user adopts a device_id and every row under
-- it. Re-claiming transfers ownership — that is what makes multi-device linking
-- and auth-session loss self-healing.
CREATE OR REPLACE FUNCTION public.sh90_claim_device(p_device_id TEXT)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sh90_claim_device: not authenticated';
  END IF;
  IF p_device_id IS NULL OR length(p_device_id) < 8 OR length(p_device_id) > 64 THEN
    RAISE EXCEPTION 'sh90_claim_device: invalid device id';
  END IF;

  INSERT INTO devices (device_id, user_id) VALUES (p_device_id, v_uid)
    ON CONFLICT (device_id) DO UPDATE SET user_id = EXCLUDED.user_id;

  UPDATE profiles          SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE exercise_logs     SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE sessions          SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE weight_log        SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE habit_log         SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE habit_notes       SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE step_log          SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE food_entries      SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE exercise_swaps    SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE workout_selection SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE support_tickets   SET user_id = v_uid WHERE device_id = p_device_id AND user_id IS DISTINCT FROM v_uid;
  UPDATE support_messages m SET user_id = v_uid
    FROM support_tickets t
    WHERE m.ticket_id = t.id AND t.device_id = p_device_id
      AND m.author = 'user' AND m.user_id IS DISTINCT FROM v_uid;
  RETURN true;
END
$fn$;

REVOKE ALL ON FUNCTION public.sh90_claim_device(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sh90_claim_device(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.sh90_claim_device(TEXT) TO authenticated;

-- Enable RLS
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercise_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE weight_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE habit_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE step_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercise_swaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_selection ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_messages ENABLE ROW LEVEL SECURITY;

-- RLS Policies: every row is visible/writable only to its owning auth user.
-- INSERTs rely on the user_id DEFAULT auth.uid(); rows created before auth
-- existed are adopted via sh90_claim_device(). Device-keyed tables also demand
-- ownership of the devices row on write, so nobody can squat rows (and unique
-- keys) under another person's device_id.
DROP POLICY IF EXISTS devices_insert ON devices;
DROP POLICY IF EXISTS devices_select ON devices;
CREATE POLICY devices_own ON devices FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS profiles_all ON profiles;
CREATE POLICY profiles_own ON profiles FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = profiles.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS exercise_logs_all ON exercise_logs;
CREATE POLICY exercise_logs_own ON exercise_logs FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = exercise_logs.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS sessions_all ON sessions;
CREATE POLICY sessions_own ON sessions FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = sessions.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS weight_log_all ON weight_log;
CREATE POLICY weight_log_own ON weight_log FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = weight_log.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS habit_log_all ON habit_log;
CREATE POLICY habit_log_own ON habit_log FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = habit_log.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS habit_notes_all ON habit_notes;
CREATE POLICY habit_notes_own ON habit_notes FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = habit_notes.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS step_log_all ON step_log;
CREATE POLICY step_log_own ON step_log FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = step_log.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS food_entries_all ON food_entries;
CREATE POLICY food_entries_own ON food_entries FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = food_entries.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS exercise_swaps_all ON exercise_swaps;
CREATE POLICY exercise_swaps_own ON exercise_swaps FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = exercise_swaps.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS workout_selection_all ON workout_selection;
CREATE POLICY workout_selection_own ON workout_selection FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = workout_selection.device_id AND d.user_id = auth.uid()));
DROP POLICY IF EXISTS support_tickets_all ON support_tickets;
CREATE POLICY support_tickets_own ON support_tickets FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM devices d WHERE d.device_id = support_tickets.device_id AND d.user_id = auth.uid()));
-- Messages are scoped by parent-ticket ownership so users can read agent
-- replies (agent rows have user_id NULL); clients may only write as 'user'.
DROP POLICY IF EXISTS support_messages_all ON support_messages;
CREATE POLICY support_messages_select ON support_messages FOR SELECT USING (
  EXISTS (SELECT 1 FROM support_tickets t WHERE t.id = ticket_id AND t.user_id = auth.uid()));
CREATE POLICY support_messages_insert ON support_messages FOR INSERT WITH CHECK (
  author = 'user' AND EXISTS (SELECT 1 FROM support_tickets t WHERE t.id = ticket_id AND t.user_id = auth.uid()));

-- The unauthenticated anon role gets no table access at all — the anon key by
-- itself is only good for the auth endpoint (anonymous sign-in).
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_exercise_logs_device_date ON exercise_logs(device_id, date);
CREATE INDEX IF NOT EXISTS idx_sessions_device_date ON sessions(device_id, date);
CREATE INDEX IF NOT EXISTS idx_habit_log_device_date ON habit_log(device_id, date);
CREATE INDEX IF NOT EXISTS idx_food_entries_device_date ON food_entries(device_id, date);
CREATE INDEX IF NOT EXISTS idx_weight_log_device_date ON weight_log(device_id, date);
CREATE INDEX IF NOT EXISTS idx_devices_user           ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_user          ON profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_exercise_logs_user     ON exercise_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user          ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_weight_log_user        ON weight_log(user_id);
CREATE INDEX IF NOT EXISTS idx_habit_log_user         ON habit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_habit_notes_user       ON habit_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_step_log_user          ON step_log(user_id);
CREATE INDEX IF NOT EXISTS idx_food_entries_user      ON food_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_exercise_swaps_user    ON exercise_swaps(user_id);
CREATE INDEX IF NOT EXISTS idx_workout_selection_user ON workout_selection(user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_user   ON support_tickets(user_id);


-- ── Nightly maintenance agent access (APPLIED to live DB 2026-08-11) ────────
-- The cloud routine that triages tickets cannot use the plain anon key any
-- more (it has no table access). These key-gated functions give it exactly
-- three capabilities: list open tickets, update status, post a reply.
-- Applied via the Management API — kept here as the definition of record.
CREATE OR REPLACE FUNCTION public.sh90_agent_tickets(p_agent_key TEXT)
RETURNS SETOF support_tickets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF p_agent_key <> '9366f4e2-11d2-47fe-9bd7-f16c11190da9-c360c355' THEN
    RAISE EXCEPTION 'sh90_agent_tickets: bad key';
  END IF;
  RETURN QUERY SELECT * FROM support_tickets
    WHERE status IN ('open','in_progress')
    ORDER BY CASE priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'normal' THEN 3 ELSE 4 END, created_at;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.sh90_agent_update_ticket(p_agent_key TEXT, p_ticket_id UUID, p_status TEXT, p_resolution_note TEXT DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF p_agent_key <> '9366f4e2-11d2-47fe-9bd7-f16c11190da9-c360c355' THEN
    RAISE EXCEPTION 'sh90_agent_update_ticket: bad key';
  END IF;
  UPDATE support_tickets SET
    status = p_status,
    resolution_note = COALESCE(p_resolution_note, resolution_note),
    resolved_at = CASE WHEN p_status IN ('resolved','closed') THEN now() ELSE resolved_at END,
    updated_at = now()
  WHERE id = p_ticket_id;
  RETURN FOUND;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.sh90_agent_reply(p_agent_key TEXT, p_ticket_id UUID, p_body TEXT)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF p_agent_key <> '9366f4e2-11d2-47fe-9bd7-f16c11190da9-c360c355' THEN
    RAISE EXCEPTION 'sh90_agent_reply: bad key';
  END IF;
  INSERT INTO support_messages (ticket_id, author, body) VALUES (p_ticket_id, 'agent', left(p_body, 10000));
  RETURN true;
END;
$fn$;

-- ── App error telemetry (APPLIED to live DB 2026-08-11) ─────────────────────
-- Client reports API failures (food/coach Gemini errors) here automatically so
-- they can be diagnosed remotely — the user never has to describe an error.
CREATE TABLE IF NOT EXISTS app_errors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL,
  user_id UUID DEFAULT auth.uid(),
  version TEXT,
  area TEXT,           -- 'food' | 'coach' | ...
  message TEXT,        -- the user-visible error message
  detail JSONB,        -- {attempts: [{model, status, err}]} from geminiGenerate
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE app_errors ENABLE ROW LEVEL SECURITY;
CREATE POLICY app_errors_insert ON app_errors FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY app_errors_select ON app_errors FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Nightly agent reads recent errors (same key as the other sh90_agent_* RPCs)
CREATE OR REPLACE FUNCTION sh90_agent_errors(p_agent_key TEXT, p_days INT DEFAULT 7)
RETURNS SETOF app_errors LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM app_errors
  WHERE p_agent_key = '9366f4e2-11d2-47fe-9bd7-f16c11190da9-c360c355'
    AND created_at > now() - make_interval(days => GREATEST(p_days, 1))
  ORDER BY created_at DESC LIMIT 200;
$$;
REVOKE ALL ON FUNCTION sh90_agent_errors(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION sh90_agent_errors(TEXT, INT) TO anon, authenticated;
