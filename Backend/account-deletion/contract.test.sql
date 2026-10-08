\set ON_ERROR_STOP on
SELECT set_config('request.jwt.claims','{"role":"service_role"}',false);
DO $$ BEGIN
 BEGIN
  PERFORM public.cup117_delete_account('begin',jsonb_build_object('operation',repeat('a',64),'owner','11111111-1111-4111-8111-111111111111','email','other@example.invalid'));
  RAISE EXCEPTION 'wrong email accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'invalid owner' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM cup117_private.deletions) THEN RAISE EXCEPTION 'rejected intent fenced account'; END IF;
END $$;
SELECT public.cup117_delete_account('begin',jsonb_build_object('operation',repeat('a',64),'owner','11111111-1111-4111-8111-111111111111','email','fixture@example.invalid'));
DO $$ DECLARE r jsonb; BEGIN
 r:=public.cup117_delete_account('resume',jsonb_build_object('operation',repeat('a',64)));
 IF r->>'owner'<>'11111111-1111-4111-8111-111111111111' OR r->>'status'<>'pending' THEN RAISE EXCEPTION 'resume did not bind original owner'; END IF;
 r:=public.cup117_delete_account('resume',jsonb_build_object('operation',repeat('b',64)));
 IF r->>'status'<>'not_started' THEN RAISE EXCEPTION 'unknown capability accepted'; END IF;
 BEGIN
  PERFORM public.cup117_delete_account('begin',jsonb_build_object('operation',repeat('a',64),'owner','22222222-2222-4222-8222-222222222222','email','other@example.invalid'));
  RAISE EXCEPTION 'foreign operation accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'foreign operation' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM public.cup117_delete_account('complete',jsonb_build_object('operation',repeat('a',64)));
  RAISE EXCEPTION 'premature completion accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'auth still present' THEN RAISE; END IF;
 END;
END $$;
INSERT INTO storage.objects VALUES('bound-roms','11111111-1111-4111-8111-111111111111/nested/original.gba');
DO $$ DECLARE r jsonb; BEGIN
 r:=public.cup117_delete_account('purge',jsonb_build_object('operation',repeat('a',64)));
 IF r->>'status'<>'pending' THEN RAISE EXCEPTION 'storage not purged first'; END IF;
END $$;
DELETE FROM storage.objects;
SELECT public.cup117_delete_account('purge',jsonb_build_object('operation',repeat('a',64)));
DELETE FROM auth.users WHERE id='11111111-1111-4111-8111-111111111111';
SELECT public.cup117_delete_account('complete',jsonb_build_object('operation',repeat('a',64)));
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id='22222222-2222-4222-8222-222222222222') THEN RAISE EXCEPTION 'deleted foreign owner'; END IF;
 IF NOT EXISTS(SELECT 1 FROM cup117_private.deletions WHERE complete) THEN RAISE EXCEPTION 'completion missing'; END IF;
END $$;
SET ROLE authenticated;
DO $$ BEGIN
 BEGIN
  PERFORM public.cup117_delete_account('resume',jsonb_build_object('operation',repeat('a',64)));
  RAISE EXCEPTION 'client can execute administrative deletion';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $$;
RESET ROLE;
