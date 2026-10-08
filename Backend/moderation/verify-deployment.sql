-- READ ONLY. Run only in Bound qevnxhngdtlyihhmvnjv after the approved deployment.
SELECT n.nspname, c.relname, c.relrowsecurity,
       has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE') AS anon_access,
       has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE') AS client_access
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'bound_moderation_private' AND c.relkind = 'r'
ORDER BY c.relname;
-- Expect five tables, RLS true, both access booleans false.

SELECT has_schema_privilege('anon', 'bound_moderation_private', 'USAGE') AS anon_schema,
       has_schema_privilege('authenticated', 'bound_moderation_private', 'USAGE') AS client_schema;
-- Both false.

SELECT n.nspname, p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS client_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'bound_moderation_private'
ORDER BY p.proname;
-- All false. Review is available only to the existing authorized database operator.

SELECT has_function_privilege('anon', 'public.cup050_friends(text,jsonb)', 'EXECUTE') AS anon_friends,
       has_function_privilege('authenticated', 'public.cup050_friends(text,jsonb)', 'EXECUTE') AS client_friends,
       has_function_privilege('anon', 'public.cup117_delete_account(text,jsonb)', 'EXECUTE') AS anon_delete,
       has_function_privilege('authenticated', 'public.cup117_delete_account(text,jsonb)', 'EXECUTE') AS client_delete,
       has_function_privilege('service_role', 'public.cup117_delete_account(text,jsonb)', 'EXECUTE') AS server_delete;
-- false, true, false, false, true.

SELECT pg_get_functiondef('public.cup050_friends(text,jsonb)'::regprocedure) AS friends_definition,
       pg_get_functiondef('public.cup117_delete_account(text,jsonb)'::regprocedure) AS deletion_definition;
-- Compare with the reviewed sources. This reads definitions only, never personal rows.
