// PhonePe PG v2 — SANDBOX ONLY. This file is intentionally not deployed.
// Deploy with verify_jwt=true after applying the matching SQL migration to a test DB.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.81.1";

const PHONEPE = "https://api-preprod.phonepe.com/apis/pg-sandbox";
const cors = {
 "access-control-allow-origin":"*",
 "access-control-allow-methods":"POST, OPTIONS",
 "access-control-allow-headers":"authorization, apikey, content-type, x-client-info",
};
const json = (body: unknown, status=200) => new Response(JSON.stringify(body),{
 status,headers:{"content-type":"application/json","cache-control":"no-store",...cors}
});
const env = (name:string) => Deno.env.get(name) || "";
async function getToken():Promise<string>{
 const params = new URLSearchParams({
   client_id:env("PHONEPE_CLIENT_ID"),
   client_version:env("PHONEPE_CLIENT_VERSION"),
   client_secret:env("PHONEPE_CLIENT_SECRET"),
   grant_type:"client_credentials"
 });
 const res=await fetch(PHONEPE+"/v1/oauth/token",{method:"POST",
   headers:{"content-type":"application/x-www-form-urlencoded"},body:params});
 if(!res.ok)throw new Error("PhonePe sandbox authentication failed");
 const data=await res.json();
 if(typeof data.access_token!=="string") throw new Error("Missing PhonePe token");
 return data.access_token;
}
async function pg(url:string,method:"GET"|"POST",body?:unknown){
 const token=await getToken();
 const response=await fetch(PHONEPE+url,{method,
  headers:{"authorization":"O-Bearer "+token,"content-type":"application/json"},
  ...(body===undefined?{}:{body:JSON.stringify(body)})});
 if(!response.ok)throw new Error("PhonePe sandbox request failed: "+response.status);
 return response.json();
}
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response(null,{status:204,headers:cors});
 if(req.method!=="POST")return json({error:"Method not allowed"},405);
 if(env("PHONEPE_SANDBOX_ENABLED")!=="true")return json({error:"Sandbox checkout disabled"},503);
 for(const key of ["PHONEPE_CLIENT_ID","PHONEPE_CLIENT_VERSION","PHONEPE_CLIENT_SECRET","PHONEPE_RETURN_URL"]){
  if(!env(key))return json({error:"Sandbox credentials not configured"},503);
 }
 const redirect=env("PHONEPE_RETURN_URL");
 if(!redirect.startsWith("https://") || new URL(redirect).username || new URL(redirect).password)
   return json({error:"Invalid server redirect configuration"},503);
 const sbUrl=env("SUPABASE_URL");
 const sbAnon=env("SUPABASE_ANON_KEY");
 const sbRole=env("SUPABASE_SERVICE_ROLE_KEY");
 if(!sbUrl||!sbAnon||!sbRole)return json({error:"Supabase server configuration missing"},503);
 const bearer=req.headers.get("authorization")||"";
 if(!bearer.startsWith("Bearer "))return json({error:"Unauthorized"},401);
 const supabase=createClient(sbUrl,sbAnon,{auth:{persistSession:false}});
 const {data:{user},error:userError}=await supabase.auth.getUser(bearer.substring(7));
 if(userError||!user)return json({error:"Unauthorized"},401);
 const db=createClient(sbUrl,sbRole,{auth:{persistSession:false}});
 let input:Record<string,unknown>;
 try{input=await req.json();}catch{return json({error:"Invalid JSON"},400);}
 try{
  if(input.action==="create"){
   const packageId=input.packageId;
   if(typeof packageId!=="string")return json({error:"Invalid package"},400);
   const {data:pack,error:packError}=await db.from("spotmate_credit_packages")
     .select("id,credits,price_paise,currency,active").eq("id",packageId).single();
   if(packError||!pack||pack.currency!=="INR"||!Number.isInteger(pack.price_paise)||
       pack.price_paise<100||!Number.isInteger(pack.credits)||pack.credits<=0)
     return json({error:"Invalid credit package"},400);
   // Packages are disabled in production; this test-only endpoint permits the
   // unchanged, pre-existing catalog while PHONEPE_SANDBOX_ENABLED is true.
   const orderId=crypto.randomUUID();
   const merchantOrderId="SM"+orderId.replaceAll("-","");
   const {error:insertError}=await db.from("spotmate_recharge_orders").insert({
    id:orderId,user_id:user.id,package_id:pack.id,credits:pack.credits,
    amount_paise:pack.price_paise,currency:"INR",provider:"phonepe_sandbox",
    provider_order_id:merchantOrderId,status:"pending"
   });
   if(insertError)throw insertError;
   let payment;
   try{
    payment=await pg("/checkout/v2/pay","POST",{
      merchantOrderId,amount:pack.price_paise,expireAfter:1200,
      paymentFlow:{type:"PG_CHECKOUT",merchantUrls:{redirectUrl:redirect}}
    });
   }catch(e){
    // Do not mark failed on an ambiguous transport error: PhonePe may have
    // created an order even if the response was lost.
    return json({error:"Checkout could not be confirmed. Check recharge history.",orderId},502);
   }
   if(payment.state!=="PENDING"||typeof payment.redirectUrl!=="string"||
      !payment.redirectUrl.startsWith("https://"))
     return json({error:"Unexpected payment session",orderId},502);
   const checkout=new URL(payment.redirectUrl);
   if(checkout.protocol!=="https:"||!checkout.hostname.endsWith(".phonepe.com"))
     return json({error:"Untrusted checkout destination",orderId},502);
   return json({orderId,checkoutUrl:checkout.toString(),status:"pending"});
  }
  if(input.action==="check"){
   const orderId=input.orderId;
   if(typeof orderId!=="string"||!/^[0-9a-f-]{36}$/i.test(orderId))
     return json({error:"Invalid order ID"},400);
   const {data:order,error:orderError}=await db.from("spotmate_recharge_orders")
    .select("id,user_id,provider,provider_order_id,amount_paise,status")
    .eq("id",orderId).eq("user_id",user.id).single();
   if(orderError||!order||order.provider!=="phonepe_sandbox")
     return json({error:"Order not found"},404);
   if(order.status==="paid")return json({status:"paid",credited:true});
   if(order.status!=="pending")return json({status:order.status,credited:false});
   const status=await pg("/checkout/v2/order/"+
      encodeURIComponent(order.provider_order_id)+"/status","GET");
   if(status.state==="COMPLETED"){
    // Trust server-to-server order status, not browser redirect/callback.
    if(status.amount!==order.amount_paise)
      return json({error:"Provider amount mismatch"},409);
    const paymentId=status.paymentDetails?.find((p:{state:string})=>p.state==="COMPLETED")?.transactionId;
    const {data:credited,error:settleError}=await db.rpc("spotmate_settle_phonepe_sandbox",{
      p_order_id:order.id,p_merchant_order_id:order.provider_order_id,
      p_amount_paise:status.amount,p_payment_id:paymentId||null
    });
    if(settleError)throw settleError;
    return json({status:"paid",credited:credited===true});
   }
   if(status.state==="FAILED"){
    await db.from("spotmate_recharge_orders").update({status:"failed"})
      .eq("id",order.id).eq("status","pending");
    return json({status:"failed",credited:false});
   }
   return json({status:"pending",credited:false});
  }
  return json({error:"Unknown action"},400);
 }catch(e){
  console.error("Sandbox payment backend error",e instanceof Error?e.message:"unknown");
  return json({error:"Unable to process recharge"},502);
 }
});
