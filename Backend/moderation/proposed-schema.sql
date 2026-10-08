-- PROPOSED ONLY: review and approve this bounded security deployment first.
BEGIN;
CREATE SCHEMA IF NOT EXISTS bound_moderation_private;
REVOKE ALL ON SCHEMA bound_moderation_private FROM PUBLIC, anon, authenticated;
CREATE TABLE bound_moderation_private.blocks (
 owner uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 target uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 label text NOT NULL CHECK(char_length(label) BETWEEN 1 AND 40),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(owner,target), CHECK(owner<>target)
);
CREATE INDEX ON bound_moderation_private.blocks(target,owner);
CREATE TABLE bound_moderation_private.reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 reporter uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 subject uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 room uuid NOT NULL, reason text NOT NULL CHECK(reason IN ('harassment','hate','sexual','violence','spam','other')),
 status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','dismissed','suspended')),
 created_at timestamptz NOT NULL DEFAULT now(), reviewed_at timestamptz,
 CHECK(reporter<>subject)
);
CREATE INDEX ON bound_moderation_private.reports(status,created_at);
CREATE INDEX ON bound_moderation_private.reports(reporter,created_at);
CREATE TABLE bound_moderation_private.suspensions (
 owner uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE bound_moderation_private.quotas (
 owner uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 window_start timestamptz NOT NULL DEFAULT now(), requests integer NOT NULL DEFAULT 0
);
CREATE TABLE bound_moderation_private.review_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 report uuid REFERENCES bound_moderation_private.reports(id) ON DELETE CASCADE,
 action text NOT NULL CHECK(action IN ('dismiss','suspend','reinstate')),
 reviewer text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE bound_moderation_private.blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE bound_moderation_private.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE bound_moderation_private.suspensions ENABLE ROW LEVEL SECURITY;
ALTER TABLE bound_moderation_private.quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE bound_moderation_private.review_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA bound_moderation_private FROM PUBLIC, anon, authenticated;

CREATE FUNCTION bound_moderation_private.denied_pair(a uuid,b uuid) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM bound_moderation_private.blocks WHERE (owner=a AND target=b) OR (owner=b AND target=a))
 OR EXISTS(SELECT 1 FROM bound_moderation_private.suspensions WHERE owner IN(a,b));
$$;
CREATE FUNCTION bound_moderation_private.clean_name(value text) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT coalesce(char_length(btrim(value)) BETWEEN 1 AND 40
 AND value !~ '[[:cntrl:]]'
 -- Baseline text safety filter only, never a claim of complete video moderation.
 AND value !~* '(https?://|www\.|@|[[:<:]](fuck|shit|cunt|nigger|faggot)[[:>:]])'
 AND value !~ U&'[\200B-\200F\202A-\202E\2066-\2069\FEFF]',false);
$$;
CREATE FUNCTION bound_moderation_private.label(value text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN bound_moderation_private.clean_name(value) THEN value ELSE 'Friend' END;
$$;
CREATE FUNCTION bound_moderation_private.block_list(actor uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('blockID',target,'displayName',bound_moderation_private.label(label)) ORDER BY created_at),'[]')
 FROM bound_moderation_private.blocks WHERE owner=actor;
$$;
CREATE FUNCTION bound_moderation_private.action(action text,payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='3s' AS $$
DECLARE actor uuid:=auth.uid(); pairing cup050_private.rooms%rowtype; peer uuid;
 stamp timestamptz:=clock_timestamp(); report_id uuid; quota bound_moderation_private.quotas%rowtype;
 denied constant jsonb:='{"ok":false}'::jsonb;
BEGIN
 PERFORM cup117_private.assert_active(actor);
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=actor AND NOT is_anonymous AND email_confirmed_at IS NOT NULL AND deleted_at IS NULL) THEN RETURN denied; END IF;
 IF action NOT IN ('block','unblock','report') OR payload IS NULL OR jsonb_typeof(payload)<>'object' OR octet_length(payload::text)>512 THEN RETURN denied; END IF;
 -- Same serialization order as the existing friend service: deletion fence first.
 PERFORM pg_advisory_xact_lock(505002026);
 INSERT INTO bound_moderation_private.quotas(owner,window_start) VALUES(actor,stamp) ON CONFLICT DO NOTHING;
 SELECT * INTO quota FROM bound_moderation_private.quotas WHERE owner=actor FOR UPDATE;
 IF stamp-quota.window_start>=interval '1 hour' THEN
  UPDATE bound_moderation_private.quotas SET window_start=stamp,requests=0 WHERE owner=actor; quota.requests:=0;
 END IF;
 IF quota.requests>=60 THEN RETURN jsonb_build_object('ok',false,'error','rate_limited'); END IF;
 UPDATE bound_moderation_private.quotas SET requests=requests+1 WHERE owner=actor;
 IF action='unblock' THEN
  IF payload-'blockID'<>'{}' OR coalesce(payload->>'blockID','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN denied; END IF;
  peer:=(payload->>'blockID')::uuid;
  DELETE FROM bound_moderation_private.blocks WHERE owner=actor AND blocks.target=peer;
  -- Unblocking does not restore a removed room or erase the other user's block.
  RETURN jsonb_build_object('ok',true,'blocks',bound_moderation_private.block_list(actor));
 END IF;
 IF coalesce(payload->>'roomID','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN denied; END IF;
 SELECT * INTO pairing FROM cup050_private.rooms WHERE id=(payload->>'roomID')::uuid AND actor IN(owner_a,owner_b);
 IF NOT FOUND THEN RETURN denied; END IF;
 peer:=CASE WHEN pairing.owner_a=actor THEN pairing.owner_b ELSE pairing.owner_a END;
 IF action='block' THEN
  IF payload-'roomID'<>'{}' OR (SELECT count(*) FROM bound_moderation_private.blocks WHERE owner=actor)>=100 THEN RETURN denied; END IF;
  IF NOT EXISTS(SELECT 1 FROM bound_moderation_private.blocks WHERE owner=actor AND target=peer) AND (SELECT count(*) FROM bound_moderation_private.blocks WHERE owner=actor)>=100 THEN RETURN jsonb_build_object('ok',false,'error','block_limit'); END IF;
  INSERT INTO bound_moderation_private.blocks(owner,target,label) VALUES(actor,peer,bound_moderation_private.label(CASE WHEN pairing.owner_a=actor THEN pairing.name_b ELSE pairing.name_a END)) ON CONFLICT DO NOTHING;
  UPDATE cup050_private.rooms SET active=false WHERE (owner_a=actor AND owner_b=peer) OR (owner_b=actor AND owner_a=peer);
  RETURN jsonb_build_object('ok',true,'blocks',bound_moderation_private.block_list(actor));
 END IF;
 IF payload-'roomID'-'reason'<>'{}' OR payload->>'reason' NOT IN ('harassment','hate','sexual','violence','spam','other') OR payload->>'reason' IS NULL
 OR EXISTS(SELECT 1 FROM bound_moderation_private.suspensions WHERE owner=actor) THEN RETURN denied; END IF;
 SELECT id INTO report_id FROM bound_moderation_private.reports WHERE reporter=actor AND room=pairing.id AND reason=payload->>'reason' AND created_at>stamp-interval '24 hours' LIMIT 1;
 IF FOUND THEN RETURN jsonb_build_object('ok',true,'reportID',report_id); END IF;
 IF (SELECT count(*) FROM bound_moderation_private.reports WHERE reporter=actor AND created_at>stamp-interval '24 hours')>=5
 OR EXISTS(SELECT 1 FROM bound_moderation_private.reports WHERE reporter=actor AND created_at>stamp-interval '1 minute') THEN RETURN jsonb_build_object('ok',false,'error','rate_limited'); END IF;
 INSERT INTO bound_moderation_private.reports(reporter,subject,room,reason) VALUES(actor,peer,pairing.id,payload->>'reason') RETURNING id INTO report_id;
 RETURN jsonb_build_object('ok',true,'reportID',report_id);
END $$;

-- Operator-only review through the existing Supabase SQL editor, never a client API.
CREATE FUNCTION bound_moderation_private.review(report_id uuid,decision text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='3s' AS $$
DECLARE target uuid;
BEGIN
 IF decision IS NULL OR decision NOT IN ('dismiss','suspend','reinstate') THEN RAISE EXCEPTION 'invalid decision'; END IF;
 SELECT subject INTO target FROM bound_moderation_private.reports WHERE id=report_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown report'; END IF;
 PERFORM cup117_private.assert_active(target);
 PERFORM pg_advisory_xact_lock(505002026);
 PERFORM 1 FROM bound_moderation_private.reports WHERE id=report_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'unknown report'; END IF;
 IF decision='suspend' THEN
  INSERT INTO bound_moderation_private.suspensions(owner) VALUES(target) ON CONFLICT DO NOTHING;
  UPDATE cup050_private.rooms SET active=false WHERE target IN(owner_a,owner_b);
  UPDATE cup050_private.invites SET consumed=true WHERE creator=target;
  UPDATE bound_moderation_private.reports SET status='suspended',reviewed_at=clock_timestamp() WHERE id=report_id;
 ELSIF decision='reinstate' THEN
  DELETE FROM bound_moderation_private.suspensions WHERE owner=target;
 ELSE
  UPDATE bound_moderation_private.reports SET status='dismissed',reviewed_at=clock_timestamp() WHERE id=report_id;
 END IF;
 INSERT INTO bound_moderation_private.review_audit(report,action,reviewer) VALUES(report_id,decision,session_user);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA bound_moderation_private FROM PUBLIC, anon, authenticated;
COMMIT;
