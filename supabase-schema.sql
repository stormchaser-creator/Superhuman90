-- SH90 Supabase Schema
-- Run this in Supabase Dashboard → SQL Editor

-- Tables
CREATE TABLE IF NOT EXISTS devices (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT UNIQUE NOT NULL, created_at TIMESTAMPTZ DEFAULT now());

CREATE TABLE IF NOT EXISTS profiles (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT UNIQUE NOT NULL REFERENCES devices(device_id), name TEXT DEFAULT '', age TEXT DEFAULT '', height TEXT DEFAULT '', goal_weight TEXT DEFAULT '', notes TEXT DEFAULT '', theme TEXT DEFAULT 'arctic', text_size TEXT DEFAULT 'medium', workout_mode TEXT DEFAULT 'gym', calorie_goal INT DEFAULT 2000, next_workout_week INT DEFAULT 1, next_workout_day INT DEFAULT 1, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now());

CREATE TABLE IF NOT EXISTS exercise_logs (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, exercise_name TEXT NOT NULL, set_index INT NOT NULL, weight TEXT, reps TEXT, done BOOLEAN DEFAULT false, completed_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date, exercise_name, set_index));

CREATE TABLE IF NOT EXISTS sessions (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, week INT NOT NULL, day INT NOT NULL, status TEXT DEFAULT 'active', started_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

CREATE TABLE IF NOT EXISTS weight_log (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, weight DECIMAL NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

CREATE TABLE IF NOT EXISTS habit_log (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, h0 BOOLEAN DEFAULT false, h1 BOOLEAN DEFAULT false, h2 BOOLEAN DEFAULT false, h3 BOOLEAN DEFAULT false, h4 BOOLEAN DEFAULT false, h5 BOOLEAN DEFAULT false, h6 BOOLEAN DEFAULT false, h7 BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

CREATE TABLE IF NOT EXISTS habit_notes (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, habit_index INT NOT NULL, note TEXT DEFAULT '', created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date, habit_index));

CREATE TABLE IF NOT EXISTS step_log (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, steps INT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

CREATE TABLE IF NOT EXISTS food_entries (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, entry_id BIGINT NOT NULL, food_text TEXT NOT NULL, logged_at TEXT, items JSONB DEFAULT '[]', calories INT DEFAULT 0, protein INT DEFAULT 0, carbs INT DEFAULT 0, fat INT DEFAULT 0, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, entry_id));

CREATE TABLE IF NOT EXISTS exercise_swaps (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), week INT NOT NULL, day INT NOT NULL, original_exercise TEXT NOT NULL, swapped_exercise TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, week, day, original_exercise));

CREATE TABLE IF NOT EXISTS workout_selection (id UUID DEFAULT gen_random_uuid() PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(device_id), date DATE NOT NULL, day INT NOT NULL, label TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), UNIQUE(device_id, date));

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

-- RLS Policies (open for anon key + device_id filtering in app)
CREATE POLICY devices_insert ON devices FOR INSERT WITH CHECK (true);
CREATE POLICY devices_select ON devices FOR SELECT USING (true);
CREATE POLICY profiles_all ON profiles FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY exercise_logs_all ON exercise_logs FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY sessions_all ON sessions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY weight_log_all ON weight_log FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY habit_log_all ON habit_log FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY habit_notes_all ON habit_notes FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY step_log_all ON step_log FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY food_entries_all ON food_entries FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY exercise_swaps_all ON exercise_swaps FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY workout_selection_all ON workout_selection FOR ALL USING (true) WITH CHECK (true);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_exercise_logs_device_date ON exercise_logs(device_id, date);
CREATE INDEX IF NOT EXISTS idx_sessions_device_date ON sessions(device_id, date);
CREATE INDEX IF NOT EXISTS idx_habit_log_device_date ON habit_log(device_id, date);
CREATE INDEX IF NOT EXISTS idx_food_entries_device_date ON food_entries(device_id, date);
CREATE INDEX IF NOT EXISTS idx_weight_log_device_date ON weight_log(device_id, date);
