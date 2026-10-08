import agora from 'npm:agora-token@2.0.5';
import { createTokenHandler } from './agora-handler.mjs';
let handler: (request: Request) => Promise<Response>;
try {
handler = createTokenHandler({
  appID: Deno.env.get('AGORA_APP_ID'),
  certificate: Deno.env.get('AGORA_APP_CERTIFICATE'),
  publishableKey: Deno.env.get('CUPCAKE_SUPABASE_PUBLISHABLE_KEY'),
  rooms: JSON.parse(Deno.env.get('AGORA_ROOMS_JSON') ?? '{}'),
  sign: ({appID, certificate, channel, uid, ttl}) => agora.RtcTokenBuilder.buildTokenWithUid(appID, certificate, channel, uid, agora.RtcRole.PUBLISHER, ttl, ttl),
});
} catch {
  handler = async () => new Response(JSON.stringify({error: "issuer_unavailable"}), {status: 503, headers: {"Content-Type": "application/json", "Cache-Control": "no-store"}});
}
Deno.serve(handler);
