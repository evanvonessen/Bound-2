-- USER-RUN HANDOFF of the exact approved Bound bundle; not executed here.
-- Target dashboard: https://supabase.com/dashboard/project/qevnxhngdtlyihhmvnjv/sql/new
-- Confirm the selected project is Bound / qevnxhngdtlyihhmvnjv before Run.
-- Contains explicit future deletion/block/suspension behavior; no obfuscation.
-- No account, storage or report data is deleted by this migration itself.
-- Baseline guard aborts if anything applied or the existing functions changed.
-- Do not rerun after success. SQL Editor execution does not add migration history;
-- retain this reviewed file and execution evidence for later reconciliation.
BEGIN;
DO $$ BEGIN
 IF to_regnamespace('bound_moderation_private') IS NOT NULL
 OR md5(pg_get_functiondef('public.cup050_friends(text,jsonb)'::regprocedure)) <> 'fe5b40ab4ec5fcd844c7bd839093215e'
 OR md5(pg_get_functiondef('public.cup117_delete_account(text,jsonb)'::regprocedure)) <> 'ec8593846751451d1266a621e8fdcc43' THEN
  RAISE EXCEPTION 'Bound deployment baseline changed; inspect before applying';
 END IF;
END $$;
-- PROPOSED ONLY: review and approve this bounded security deployment first.

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

-- PROPOSED ONLY. Exact existing service copied behind a checked public wrapper.

CREATE OR REPLACE FUNCTION cup050_private.bound_friend_service_v1(action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare
  actor uuid := auth.uid(); stamp timestamptz := clock_timestamp();
  quota cup050_private.limits%rowtype; invitation cup050_private.invites%rowtype;
  pairing cup050_private.rooms%rowtype; nickname text; code text; selected uuid;
  result jsonb; denied constant jsonb := '{"ok":false}'::jsonb;
begin
  perform cup117_private.assert_active(actor);
  -- JWT identity alone is insufficient: consult the current account on each call.
  if actor is null or not exists (select 1 from auth.users u where u.id=actor
      and u.is_anonymous=false and u.email_confirmed_at is not null and u.deleted_at is null) then return denied; end if;
  if action is null or action not in ('create','accept','list','room','remove') or payload is null
      or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>512 then return denied; end if;
  -- A bounded waiting lock serializes this development feature; ordinary
  -- concurrent renewals wait rather than receiving a false authorization denial.
  -- It also prevents cross-owner room-count races without lock-order deadlocks.
  perform pg_advisory_xact_lock(505002026);
  insert into cup050_private.limits(owner,window_start) values(actor,stamp) on conflict do nothing;
  select * into quota from cup050_private.limits where owner=actor for update;
  if stamp-quota.window_start >= interval '1 hour' then
    update cup050_private.limits set window_start=stamp,requests=0,creates=0,guesses=0 where owner=actor;
    quota.requests:=0; quota.creates:=0; quota.guesses:=0;
  end if;
  if quota.requests>=240 then return denied; end if;
  update cup050_private.limits set requests=requests+1 where owner=actor;
  if action='create' then
    if jsonb_typeof(payload->'displayName') is distinct from 'string' or payload- 'displayName'<>'{}'::jsonb or quota.creates>=5 then return denied; end if;
    update cup050_private.limits set creates=creates+1 where owner=actor;
    nickname:=btrim(payload->>'displayName');
    if nickname is null or char_length(nickname) not between 1 and 40 or nickname ~ '[[:cntrl:]]' then return denied; end if;
    if (select count(*) from cup050_private.rooms where active and actor in (owner_a,owner_b))>=20 then return denied; end if;
    -- Only the newest code is outstanding. Never retain plaintext codes.
    update cup050_private.invites set consumed=true where creator=actor and not consumed;
    code:=upper(encode(extensions.gen_random_bytes(8),'hex'));
    insert into cup050_private.invites(digest,creator,display_name,expires_at)
      values(extensions.digest(code,'sha256'),actor,nickname,stamp+interval '10 minutes');
    return jsonb_build_object('ok',true,'code',code,'expiresAt',stamp+interval '10 minutes');
  elsif action='accept' then
    if jsonb_typeof(payload->'displayName') is distinct from 'string' or jsonb_typeof(payload->'code') is distinct from 'string' or payload- 'code'- 'displayName'<>'{}'::jsonb or quota.guesses>=10 then return denied; end if;
    -- Return denials rather than raising: invalid guesses commit their quota.
    update cup050_private.limits set guesses=guesses+1 where owner=actor;
    code:=upper(btrim(payload->>'code')); nickname:=btrim(payload->>'displayName');
    if code is null or code !~ '^[0-9A-F]{16}$' or nickname is null
       or char_length(nickname) not between 1 and 40 or nickname ~ '[[:cntrl:]]' then return denied; end if;
    select * into invitation from cup050_private.invites where digest=extensions.digest(code,'sha256') for update;
    if found then perform cup117_private.assert_active(invitation.creator); end if;
    if invitation.creator is null or invitation.consumed or invitation.expires_at<=stamp or invitation.creator=actor then return denied; end if;
    if not exists(select 1 from auth.users u where u.id=invitation.creator and u.is_anonymous=false and u.email_confirmed_at is not null and u.deleted_at is null) then return denied; end if;
    if exists(select 1 from cup050_private.rooms where active and ((owner_a=actor and owner_b=invitation.creator) or (owner_b=actor and owner_a=invitation.creator))) then return denied; end if;
    if (select count(*) from cup050_private.rooms where active and actor in (owner_a,owner_b))>=20
       or (select count(*) from cup050_private.rooms where active and invitation.creator in (owner_a,owner_b))>=20 then return denied; end if;
    insert into cup050_private.rooms(owner_a,owner_b,name_a,name_b) values(invitation.creator,actor,invitation.display_name,nickname) returning * into pairing;
    update cup050_private.invites set consumed=true where digest=invitation.digest;
    return jsonb_build_object('ok',true,'room',jsonb_build_object('roomID',pairing.id,'displayName',pairing.name_a));
  elsif action='list' then
    if payload<>'{}'::jsonb then return denied; end if;
    select coalesce(jsonb_agg(jsonb_build_object('roomID',r.id,'displayName',case when r.owner_a=actor then r.name_b else r.name_a end) order by r.id),'[]'::jsonb)
      into result from cup050_private.rooms r where r.active and actor in(r.owner_a,r.owner_b);
    return jsonb_build_object('ok',true,'rooms',result);
  else
    if jsonb_typeof(payload->'roomID') is distinct from 'string' or payload- 'roomID'<>'{}'::jsonb or coalesce(payload->>'roomID','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return denied; end if;
    selected:=(payload->>'roomID')::uuid;
    select * into pairing from cup050_private.rooms where id=selected and active and actor in(owner_a,owner_b) for update;
    if not found then return denied; end if;
    perform cup117_private.assert_active(pairing.owner_a);
    perform cup117_private.assert_active(pairing.owner_b);
    if action='remove' then
      update cup050_private.rooms set active=false where id=selected;
      return jsonb_build_object('ok',true);
    end if;
    return jsonb_build_object('ok',true,'room',jsonb_build_object('roomID',pairing.id,
      'channel','cup050_'||replace(pairing.id::text,'-',''),
      'uid',case when pairing.owner_a=actor then 1 else 2 end,
      'remoteUID',case when pairing.owner_a=actor then 2 else 1 end));
  end if;
end;
$function$
;
REVOKE ALL ON FUNCTION cup050_private.bound_friend_service_v1(text,jsonb) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.cup050_friends(action text,payload jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' SET lock_timeout='3s' AS $$
DECLARE actor uuid:=auth.uid(); peer uuid; pairing cup050_private.rooms%rowtype; answer jsonb; item jsonb; safe_rooms jsonb:='[]';
 denied constant jsonb:='{"ok":false}'::jsonb;
BEGIN
 PERFORM cup117_private.assert_active(actor);
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=actor AND NOT is_anonymous AND email_confirmed_at IS NOT NULL AND deleted_at IS NULL) THEN RETURN denied; END IF;
 IF payload IS NULL OR jsonb_typeof(payload)<>'object' OR octet_length(payload::text)>512 THEN RETURN denied; END IF;
 IF action IN ('report','block','unblock') THEN RETURN bound_moderation_private.action(action,payload); END IF;
 IF action NOT IN ('create','accept','list','room','remove') THEN RETURN denied; END IF;
 PERFORM pg_advisory_xact_lock(505002026);
 IF EXISTS(SELECT 1 FROM bound_moderation_private.suspensions WHERE owner=actor) THEN RETURN denied; END IF;
 IF action IN ('create','accept') AND NOT bound_moderation_private.clean_name(payload->>'displayName') THEN RETURN jsonb_build_object('ok',false,'error','name_not_allowed'); END IF;
 IF action='accept' THEN
  SELECT creator INTO peer FROM cup050_private.invites WHERE digest=extensions.digest(upper(btrim(payload->>'code')),'sha256');
  IF peer IS NOT NULL AND bound_moderation_private.denied_pair(actor,peer) THEN RETURN denied; END IF;
 ELSIF action='room' THEN
  IF coalesce(payload->>'roomID','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN denied; END IF;
  SELECT * INTO pairing FROM cup050_private.rooms WHERE id=(payload->>'roomID')::uuid AND active AND actor IN(owner_a,owner_b);
  IF NOT FOUND OR bound_moderation_private.denied_pair(pairing.owner_a,pairing.owner_b) THEN RETURN denied; END IF;
 END IF;
 answer:=cup050_private.bound_friend_service_v1(action,payload);
 IF answer->>'ok'<>'true' THEN RETURN answer; END IF;
 IF action='list' THEN
  -- Hide unsafe legacy labels without removing the ability to report or block.
  FOR item IN SELECT value FROM jsonb_array_elements(answer->'rooms') LOOP
   SELECT * INTO pairing FROM cup050_private.rooms WHERE id=(item->>'roomID')::uuid AND actor IN(owner_a,owner_b);
   IF FOUND AND NOT bound_moderation_private.denied_pair(pairing.owner_a,pairing.owner_b) THEN
    safe_rooms:=safe_rooms||jsonb_build_array(jsonb_build_object('roomID',item->>'roomID','displayName',bound_moderation_private.label(item->>'displayName')));
   END IF;
  END LOOP;
  answer:=jsonb_set(answer,'{rooms}',safe_rooms);
  answer:=answer||jsonb_build_object('blocks',bound_moderation_private.block_list(actor));
 ELSIF action='accept' THEN
  answer:=jsonb_set(answer,'{room,displayName}',to_jsonb(bound_moderation_private.label(answer->'room'->>'displayName')));
 END IF;
 RETURN answer;
END $$;
REVOKE ALL ON FUNCTION public.cup050_friends(text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cup050_friends(text,jsonb) TO authenticated;

-- PROPOSED ONLY. Do not apply without explicit deployment approval.
-- Snapshot: Bound project qevnxhngdtlyihhmvnjv, 2026-10-08.
-- Preserve existing legacy clients; email confirmation uses the actual Auth email.

CREATE OR REPLACE FUNCTION public.cup117_delete_account(action text, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare op text := payload->>'operation'; target_owner uuid; job cup117_private.deletions%rowtype; objects jsonb;
begin
 if coalesce(auth.jwt()->>'role','') <> 'service_role' then raise exception 'forbidden' using errcode='42501'; end if;
 if op is null or op !~ '^[a-f0-9]{64}$' then raise exception 'invalid'; end if;
 -- Exclusive acquisition drains all prior guarded transactions BEFORE recording
 -- the fence. Row triggers wait on this same lock then see the committed marker.
 perform pg_advisory_xact_lock(11720260925);
 if exists(select 1 from cup117_private.cancelled_capabilities where operation=op) then
   return '{"ok":true,"status":"cancelled"}'::jsonb;
 end if;
 if action='begin' then
   target_owner := (payload->>'owner')::uuid;
   if not exists(select 1 from auth.users where id=target_owner and deleted_at is null and is_anonymous=false
       and email_confirmed_at is not null and (
         (payload ? 'email' and lower(btrim(email, E' \t\r\n'))=payload->>'email')
         or (not (payload ? 'email') and raw_user_meta_data->>'cupcake_username_v1'=payload->>'username')
       )) then raise exception 'invalid owner'; end if;
   insert into cup117_private.deletions(owner) values(target_owner) on conflict(owner) do nothing;
   insert into cup117_private.capabilities(operation,owner) values(op,target_owner) on conflict(operation) do nothing;
 end if;
 select d.* into job from cup117_private.deletions d
 join cup117_private.capabilities c on c.owner=d.owner where c.operation=op;
 if not found then
   if action='cancel' then
     insert into cup117_private.cancelled_capabilities(operation) values(op);
     return '{"ok":true,"status":"cancelled"}'::jsonb;
   end if;
   if action='resume' then return '{"ok":true,"status":"not_started"}'::jsonb; end if;
   raise exception 'unknown operation';
 end if;
 if action='begin' and job.owner <> target_owner then raise exception 'foreign operation'; end if;
 if job.complete then return jsonb_build_object('ok',true,'status','complete'); end if;
 target_owner := job.owner;
 if action in ('begin','resume','cancel') then return jsonb_build_object('ok',true,'status','pending','owner',target_owner); end if;
 if action='objects' then
   select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)),'[]') into objects
   from (select bucket_id,name from storage.objects where bucket_id in ('cup040-saves','cup071-covers','bound-roms')
      and split_part(name,'/',1)=target_owner::text order by bucket_id,name limit 100) s;
   return jsonb_build_object('ok',true,'objects',objects);
 end if;
 if action='purge' then
   if exists(select 1 from storage.objects where bucket_id in ('cup040-saves','cup071-covers','bound-roms') and split_part(name,'/',1)=target_owner::text) then
     return '{"ok":true,"status":"pending"}'::jsonb;
   end if;
   delete from cup041_v3_private.imports where owner=target_owner;
   delete from cup041_v3_private.observations where owner=target_owner;
   delete from cup041_v3_private.values where owner=target_owner;
   delete from cup041_v3_private.markers where owner=target_owner;
   delete from cup041_v3_private.receipts where owner=target_owner;
   delete from cup041_v3_private.actors where owner=target_owner;
   delete from cup041_v3_private.counters where owner=target_owner;
   delete from cup041_v3_private.branches where owner=target_owner;
   delete from cup041_v3_private.payloads where owner=target_owner;
   delete from cup041_v3_private.games where owner=target_owner;
   delete from cup041_private.actors where owner=target_owner;
   delete from cup041_private.revisions where owner=target_owner;
   delete from cup041_private.receipts where owner=target_owner;
   delete from cup041_private.entities where owner=target_owner;
   delete from cup041_private.games where owner=target_owner;
   delete from public.cup040_catalogue where owner_id=target_owner;
   if to_regclass('public.bound_roms') is not null then
     execute 'delete from public.bound_roms where owner=$1' using target_owner;
   end if;
   delete from public.bound_note_revisions where owner=target_owner;
   delete from public.bound_autosave_revisions where owner=target_owner;
   delete from cup050_private.invites where creator=target_owner;
   delete from cup050_private.limits where owner=target_owner;
   delete from cup050_private.rooms where target_owner in(owner_a,owner_b);
   return '{"ok":true,"status":"ready"}'::jsonb;
 elsif action='complete' then
   if exists(select 1 from auth.users where id=target_owner) then raise exception 'auth still present'; end if;
   update cup117_private.deletions set complete=true where owner=target_owner;
   return '{"ok":true,"status":"complete"}'::jsonb;
 end if;
 raise exception 'invalid action';
end $function$
;
REVOKE ALL ON FUNCTION public.cup117_delete_account(text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cup117_delete_account(text,jsonb) TO service_role;

COMMIT;
