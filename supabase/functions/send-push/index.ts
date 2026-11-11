import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
// Compatibility endpoint: old apps already inserted their notifications before
// invoking this endpoint. The durable outbox is now the only sender.
serve(async(req)=>{
  if(req.method!=="POST") return new Response("Method not allowed",{status:405});
  const token=req.headers.get("authorization")?.replace(/^Bearer\s+/i,"");
  if(!token) return new Response("Unauthorized",{status:401});
  const client=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!);
  const {data,error}=await client.auth.getUser(token);
  if(error || !data.user) return new Response("Unauthorized",{status:401});
  return Response.json({queued:true,delivery:"notification_outbox"},{status:202});
});
