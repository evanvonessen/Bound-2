-- Local disposable PostgreSQL fixture only. Never apply to Supabase.
DO $$ DECLARE r text; BEGIN FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('CREATE ROLE %I',r); END IF; END LOOP; END $$;
CREATE SCHEMA auth; CREATE SCHEMA storage; CREATE SCHEMA cup117_private; CREATE SCHEMA cup050_private;
CREATE SCHEMA cup041_private; CREATE SCHEMA cup041_v3_private;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT (auth.jwt()->>'sub')::uuid $$;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,deleted_at timestamptz,is_anonymous boolean DEFAULT false,email_confirmed_at timestamptz,raw_user_meta_data jsonb DEFAULT '{}');
CREATE TABLE cup117_private.deletions(owner uuid PRIMARY KEY,complete boolean DEFAULT false);
CREATE TABLE cup117_private.capabilities(operation text PRIMARY KEY,owner uuid);
CREATE TABLE cup117_private.cancelled_capabilities(operation text PRIMARY KEY);
CREATE TABLE storage.objects(bucket_id text,name text);
CREATE TABLE cup050_private.rooms(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),owner_a uuid,owner_b uuid,name_a text,name_b text,active boolean DEFAULT true,created_at timestamptz DEFAULT now());
CREATE TABLE cup050_private.invites(digest bytea PRIMARY KEY,creator uuid,display_name text,expires_at timestamptz,consumed boolean DEFAULT false);
CREATE TABLE cup050_private.limits(owner uuid PRIMARY KEY,window_start timestamptz,requests integer DEFAULT 0,creates integer DEFAULT 0,guesses integer DEFAULT 0);
CREATE TABLE public.cup040_catalogue(owner_id uuid);
CREATE TABLE public.bound_roms(owner uuid);
CREATE TABLE public.bound_note_revisions(owner uuid);
CREATE TABLE public.bound_autosave_revisions(owner uuid);
DO $$ DECLARE s text; t text; BEGIN
 FOREACH s IN ARRAY ARRAY['cup041_private','cup041_v3_private'] LOOP
  FOREACH t IN ARRAY ARRAY['imports','observations','values','markers','receipts','actors','counters','branches','payloads','games','revisions','entities'] LOOP
   EXECUTE format('CREATE TABLE %I.%I(owner uuid)',s,t);
  END LOOP;
 END LOOP;
END $$;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES ('11111111-1111-4111-8111-111111111111','Fixture@Example.invalid',now()),('22222222-2222-4222-8222-222222222222','other@example.invalid',now());
