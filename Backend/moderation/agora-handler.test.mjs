import test from 'node:test';
import assert from 'node:assert/strict';
import {createTokenHandler} from './agora-handler.mjs';
const owner='11111111-1111-4111-8111-111111111111';
const room='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const json=(body,status=200)=>new Response(JSON.stringify(body),{status});
function fixture({deny=false,deleted=false,staticRoom=false}={}) {
 const calls=[];let signed=0;
 const handler=createTokenHandler({appID:'a'.repeat(32),certificate:'b'.repeat(32),publishableKey:'synthetic-public',rooms:staticRoom?{legacy:{channel:'legacy',members:[{ownerID:owner,uid:1},{ownerID:'22222222-2222-4222-8222-222222222222',uid:2}]}}:{},now:()=>1000,
 sign:args=>{signed++;assert.equal(args.ttl,60);return 'synthetic-rtc-token';},fetchImpl:async(url,options)=>{
  calls.push(url);assert.equal(options.headers.Authorization,'Bearer synthetic.valid.session');
  if(url.endsWith('/auth/v1/user'))return json({id:owner,is_anonymous:false,role:'authenticated',email_confirmed_at:'2026-01-01T00:00:00Z'},deleted?401:200);
  if(url.endsWith('/cup117_account_active'))return json(true);
  if(url.endsWith('/cup050_friends')) {
   assert.deepEqual(JSON.parse(options.body),{action:'room',payload:{roomID:room}});
   return json(deny?{ok:false}:{ok:true,room:{roomID:room,channel:'cup050_'+room.replaceAll('-',''),uid:1,remoteUID:2}});
  }
  throw Error('unexpected endpoint');
 }});
 return {calls,signed:()=>signed,request:()=>handler(new Request('https://fixture.invalid/agora-token',{method:'POST',headers:{Authorization:'Bearer synthetic.valid.session','Content-Type':'application/json'},body:JSON.stringify({roomID:staticRoom?'legacy':room})}))};
}
test('allowed dynamic room gets a 60-second lease after checked membership',async()=>{
 const f=fixture();const r=await f.request();assert.equal(r.status,200);const value=await r.json();assert.equal(value.expiresAt-value.issuedAt,60);assert.equal(f.signed(),1);assert.equal(f.calls.length,3);
});
test('blocked or suspended dynamic room cannot issue or renew a token, including old client request',async()=>{
 const f=fixture({deny:true});assert.equal((await f.request()).status,403);assert.equal(f.signed(),0);
});
test('deleted or revoked Auth identity is denied before membership and signing',async()=>{
 const f=fixture({deleted:true});assert.equal((await f.request()).status,401);assert.equal(f.signed(),0);assert.equal(f.calls.length,1);
});
test('legacy static configuration cannot bypass moderation gates',async()=>{
 const f=fixture({staticRoom:true});assert.equal((await f.request()).status,403);assert.equal(f.signed(),0);
});
