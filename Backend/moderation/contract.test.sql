\set ON_ERROR_STOP on
-- Disposable fixtures only. Exercise authenticated roles as the real RPC receives them.
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('33333333-3333-4333-8333-333333333333','third@example.invalid',now());
INSERT INTO cup050_private.rooms(id,owner_a,owner_b,name_a,name_b) VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','Player A','Player B');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',false);
SET ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.cup050_friends('report','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","reason":"harassment"}');
 IF r->>'ok'<>'true' OR r->>'reportID' IS NULL THEN RAISE EXCEPTION 'durable report rejected'; END IF;
 r:=public.cup050_friends('report','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","reason":"harassment"}');
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'duplicate report was not idempotent'; END IF;
 r:=public.cup050_friends('report','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","reason":"spam"}');
 IF r->>'error'<>'rate_limited' THEN RAISE EXCEPTION 'report flood accepted'; END IF;
 r:=public.cup050_friends('report','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","reason":"harassment","target":"33333333-3333-4333-8333-333333333333"}');
 IF r->>'ok'<>'false' THEN RAISE EXCEPTION 'request selected target accepted'; END IF;
 r:=public.cup050_friends('block','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}');
 IF r->>'ok'<>'true' OR jsonb_array_length(r->'blocks')<>1 THEN RAISE EXCEPTION 'block failed'; END IF;
 r:=public.cup050_friends('room','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}');
 IF r->>'ok'<>'false' THEN RAISE EXCEPTION 'blocked room can issue token'; END IF;
 BEGIN PERFORM * FROM bound_moderation_private.reports; RAISE EXCEPTION 'client can read private reports'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM bound_moderation_private.review(gen_random_uuid(),'suspend'); RAISE EXCEPTION 'client can moderate users'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM bound_moderation_private.reports)<>1 THEN RAISE EXCEPTION 'report idempotence failed'; END IF;
 IF EXISTS(SELECT 1 FROM cup050_private.rooms WHERE active) THEN RAISE EXCEPTION 'block kept connection active'; END IF;
 IF NOT bound_moderation_private.denied_pair('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111') THEN RAISE EXCEPTION 'block not bidirectional'; END IF;
END $$;
-- A blocked peer cannot accept the other side's still-valid invite, even using old client calls.
INSERT INTO cup050_private.invites(digest,creator,display_name,expires_at) VALUES(extensions.digest('0123456789ABCDEF','sha256'),'11111111-1111-4111-8111-111111111111','Player A',now()+interval '10 minutes');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"22222222-2222-4222-8222-222222222222"}',false);
SET ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.cup050_friends('accept','{"code":"0123456789ABCDEF","displayName":"Player B"}'); IF r->>'ok'<>'false' THEN RAISE EXCEPTION 'blocked invite accepted'; END IF;
 r:=public.cup050_friends('room','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}'); IF r->>'ok'<>'false' THEN RAISE EXCEPTION 'peer token allowed'; END IF;
 r:=public.cup050_friends('unblock','{"blockID":"11111111-1111-4111-8111-111111111111"}'); IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'unblock own list failed'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM bound_moderation_private.blocks) THEN RAISE EXCEPTION 'peer erased another owner block'; END IF; END $$;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"33333333-3333-4333-8333-333333333333"}',false);
SET ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.cup050_friends('report','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","reason":"hate"}'); IF r->>'ok'<>'false' THEN RAISE EXCEPTION 'foreign room report accepted'; END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',false);
SET ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.cup050_friends('unblock','{"blockID":"22222222-2222-4222-8222-222222222222"}'); IF r->>'ok'<>'true' OR jsonb_array_length(r->'blocks')<>0 THEN RAISE EXCEPTION 'owner unblock failed'; END IF;
 r:=public.cup050_friends('create','{"displayName":"unsafe@example.invalid"}'); IF r->>'error'<>'name_not_allowed' THEN RAISE EXCEPTION 'text filter bypassed'; END IF;
END $$;
RESET ROLE;
DO $$ DECLARE r uuid; BEGIN
 IF EXISTS(SELECT 1 FROM cup050_private.rooms WHERE active) THEN RAISE EXCEPTION 'unblock reactivated a room'; END IF;
 IF bound_moderation_private.clean_name(U&'Player\202E') THEN RAISE EXCEPTION 'bidi filter bypassed'; END IF;
 SELECT id INTO r FROM bound_moderation_private.reports LIMIT 1;
 PERFORM bound_moderation_private.review(r,'suspend');
 IF NOT EXISTS(SELECT 1 FROM bound_moderation_private.suspensions WHERE owner='22222222-2222-4222-8222-222222222222') THEN RAISE EXCEPTION 'suspension missing'; END IF;
END $$;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"22222222-2222-4222-8222-222222222222"}',false);
SET ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN r:=public.cup050_friends('create','{"displayName":"Player B"}'); IF r->>'ok'<>'false' THEN RAISE EXCEPTION 'suspended account can invite'; END IF; END $$;
RESET ROLE;
DO $$ DECLARE r uuid; BEGIN SELECT id INTO r FROM bound_moderation_private.reports LIMIT 1; PERFORM bound_moderation_private.review(r,'reinstate'); END $$;
UPDATE bound_moderation_private.quotas SET requests=60 WHERE owner='11111111-1111-4111-8111-111111111111';
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}',false);
SET ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN r:=public.cup050_friends('block','{"roomID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}'); IF r->>'error'<>'rate_limited' THEN RAISE EXCEPTION 'action rate limit bypassed'; END IF; END $$;
RESET ROLE;
-- Stale JWT after Auth deletion must fail current-user gate and cannot queue a report.
DELETE FROM auth.users WHERE id='11111111-1111-4111-8111-111111111111';
SET ROLE authenticated;
DO $$ BEGIN BEGIN PERFORM public.cup050_friends('list','{}'); RAISE EXCEPTION 'stale JWT accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $$;
RESET ROLE;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM bound_moderation_private.reports) THEN RAISE EXCEPTION 'deleted account report metadata retained'; END IF; END $$;
