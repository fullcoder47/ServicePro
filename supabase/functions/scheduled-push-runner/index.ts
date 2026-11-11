import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
// Existing scheduler entry point now uses the same retryable outbox worker.
serve(async(req)=>{
  const secret=Deno.env.get("NOTIFICATION_JOB_SECRET");
  if(!secret || req.headers.get("x-job-secret")!==secret) return new Response("Unauthorized",{status:401});
  if(req.method!=="POST") return new Response("Method not allowed",{status:405});
  const response=await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/notification-worker`,{
    method:"POST",headers:{"x-job-secret":secret},signal:AbortSignal.timeout(50000),
  });
  return new Response(await response.text(),{status:response.status,headers:{"Content-Type":"application/json"}});
});
