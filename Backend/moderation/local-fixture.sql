-- LOCAL ONLY after account-deletion fixture; never apply to live Supabase.
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE FUNCTION cup117_private.assert_active(actor uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 PERFORM pg_advisory_xact_lock_shared(11720260925);
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=actor AND deleted_at IS NULL)
 OR EXISTS(SELECT 1 FROM cup117_private.deletions WHERE owner=actor) THEN RAISE EXCEPTION 'account unavailable' USING errcode='42501'; END IF;
END $$;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.jwt(),auth.uid() TO authenticated;
