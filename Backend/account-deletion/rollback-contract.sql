-- Reviewed predeployment snapshot of Bound qevnxhngdtlyihhmvnjv. Operator rollback only.
-- Retain private moderation tables and history; never erase reports to roll back code.
BEGIN;
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
       and email_confirmed_at is not null and raw_user_meta_data->>'cupcake_username_v1'=payload->>'username') then raise exception 'invalid owner'; end if;
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
