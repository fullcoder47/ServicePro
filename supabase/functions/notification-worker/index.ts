import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { getGoogleAccessToken } from "../_shared/fcm.ts";
import { classifyFcm } from "../_shared/push_policy.ts";

// Called by pg_cron with a Vault-managed secret. No user-controlled recipients.
serve(async (req) => {
  const secret=Deno.env.get("NOTIFICATION_JOB_SECRET");
  if(!secret || req.headers.get("x-job-secret")!==secret) return new Response("Unauthorized",{status:401});
  if(req.method!=="POST") return new Response("Method not allowed",{status:405});
  const client=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  try {
    const {error:scheduleError}=await client.rpc("servicepro_enqueue_schedules");
    if(scheduleError) throw new Error("schedule_enqueue_failed");
    const {error:reminderError}=await client.rpc("servicepro_enqueue_ticket_reminders");
    if(reminderError) throw new Error("reminder_enqueue_failed");
    const {data:jobs,error}=await client.rpc("servicepro_claim_push_jobs",{p_limit:20});
    if(error) throw new Error("job_claim_failed");
    if(!jobs?.length) return Response.json({processed:0});
    let accessToken:string;
    try {
      accessToken=await getGoogleAccessToken(Deno.env.get("FIREBASE_CLIENT_EMAIL")!,Deno.env.get("FIREBASE_PRIVATE_KEY")!.replace(/\\n/g,"\n"));
    } catch(_) {
      for(const job of jobs) await client.rpc("servicepro_finish_push_job",{p_id:job.id,p_lease:job.lease_token,p_ok:false,p_tokens:[],p_error:"firebase_auth_failed"});
      return Response.json({error:"firebase_auth_failed"},{status:500});
    }
    const project=Deno.env.get("FIREBASE_PROJECT_ID")!;
    const started=Date.now();
    let processed=0;
    for(const job of jobs) {
      let ok=true;
      const delivered:string[]=[];
      let reason="";
      try {
        if(Date.now()-started>45000) {
          await client.rpc("servicepro_finish_push_job",{p_id:job.id,p_lease:job.lease_token,p_ok:false,p_tokens:[],p_error:"worker_time_budget"});
          continue;
        }
        // Keep old events in the inbox without a burst of stale phone alerts.
        if(Date.now()-Date.parse(job.created_at)>24*60*60*1000) {
          await client.rpc("servicepro_finish_push_job",{p_id:job.id,p_lease:job.lease_token,p_ok:true,p_tokens:[],p_error:"expired_event"});
          processed++;continue;
        }
        let muted=false;
        if(job.chat_room_id) {
          const {data:pref,error:prefError}=await client.from("chat_preferences").select("muted_until").eq("room_id",job.chat_room_id).eq("profile_id",job.profile_id).maybeSingle();
          if(prefError) throw new Error("preference_lookup_failed");
          muted=!!pref?.muted_until && Date.parse(pref.muted_until)>Date.now();
        }
        if(!muted) {
          const {data:tokens,error:tokenError}=await client.from("device_tokens").select("token").eq("profile_id",job.profile_id).eq("is_active",true);
          if(tokenError) throw new Error("token_lookup_failed");
          if(!tokens?.length) { ok=false;reason="no_active_device"; }
          const seen=new Set(job.delivered_tokens??[]);
          // Small parallel batches keep each lease within the worker deadline.
          for(let i=0;i<(tokens??[]).length;i+=5) {
            const outcomes=await Promise.all((tokens??[]).slice(i,i+5).map(async ({token})=>{
              if(seen.has(token)) return;
              try {
                const response=await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`,{
                  method:"POST",signal:AbortSignal.timeout(12000),
                  headers:{Authorization:`Bearer ${accessToken}`,"Content-Type":"application/json"},
                  body:JSON.stringify({message:{token,
                    notification:{title:job.title,body:job.body},
                    data:{notification_id:job.id,profile_id:job.profile_id,type:job.notification_type,
                      ticket_id:job.ticket_id??"",chat_room_id:job.chat_room_id??"",chat_message_id:job.chat_message_id??"",ad_group_id:job.ad_group_id??""},
                    android:{priority:"HIGH",notification:{channel_id:"servicepro_alerts_v2",icon:"ic_notification",sound:"servicepro_sound",tag:job.id}},
                    apns:{headers:{"apns-collapse-id":job.id},payload:{aps:{sound:"default"}}},
                    webpush:{headers:{Urgency:"high"},notification:{
                      icon:"/icons/Icon-192.png",tag:job.id,
                      data:{notification_id:job.id,profile_id:job.profile_id,type:job.notification_type,
                        ticket_id:job.ticket_id??"",chat_room_id:job.chat_room_id??"",
                        chat_message_id:job.chat_message_id??"",ad_group_id:job.ad_group_id??""},
                    }},
                  }}),
                });
                const body=await response.json().catch(()=>({}));
                const result=classifyFcm(response.status,body);
                if(result==="success") { delivered.push(token);return; }
                if(result==="unregistered") {
                  const {error:disableError}=await client.from("device_tokens").update({is_active:false}).eq("token",token).eq("profile_id",job.profile_id);
                  if(disableError) throw new Error("token_disable_failed");
                  delivered.push(token);return;
                }
                ok=false;reason=`fcm_http_${response.status}`;
              } catch(_) { ok=false;reason="network_or_delivery_failure"; }
            }));
            void outcomes;
          }
        }
      } catch(_) { ok=false;reason="job_processing_failed"; }
      const {error:finishError}=await client.rpc("servicepro_finish_push_job",{
        p_id:job.id,p_lease:job.lease_token,p_ok:ok,p_tokens:delivered,p_error:reason,
      });
      if(finishError) throw new Error("job_finish_failed");
      processed++;
    }
    return Response.json({processed});
  } catch(_) {
    // Never return credentials, tokens or Google response bodies.
    return Response.json({error:"worker_failed_jobs_will_retry"},{status:500});
  }
});
