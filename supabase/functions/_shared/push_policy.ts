export function classifyFcm(status:number,body:{error?:{details?:Array<{errorCode?:string}>}}):"success"|"unregistered"|"retry" {
  if(status>=200 && status<300) return "success";
  // A 429/5xx/auth/config failure must never disable a valid device token.
  return body.error?.details?.some((item)=>item.errorCode==="UNREGISTERED") ? "unregistered" : "retry";
}
