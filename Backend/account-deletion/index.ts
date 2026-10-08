import { createDeletionHandler } from './handler.mjs';
// Platform JWT verification must be disabled for this endpoint: begin performs
// Auth getUser validation; resume uses its unguessable preauthorized job token.
// Never log requests, authorization headers, operation tokens or service keys.
Deno.serve(createDeletionHandler({
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  publishableKey: Deno.env.get('CUPCAKE_SUPABASE_PUBLISHABLE_KEY'),
}));
