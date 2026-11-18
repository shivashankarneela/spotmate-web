import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'npm:@supabase/supabase-js@2.81.1';
const env=(k:string)=>Deno.env.get(k)??'';
const json=(x:unknown,status=200)=>new Response(JSON.stringify(x),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
const enc=new TextEncoder();
async function signature(secret:string,raw:string){
 const k=await crypto.subtle.importKey('raw',enc.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return [...new Uint8Array(await crypto.subtle.sign('HMAC',k,enc.encode(raw)))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
function equal(a:string,b:string){if(!/^[0-9a-f]{64}$/i.test(a)|| !/^[0-9a-f]{64}$/i.test(b))return false;let x=0;for(let i=0;i<64;i++)x|=a.toLowerCase().charCodeAt(i)^b.toLowerCase().charCodeAt(i);return x===0;}
async function gateway(path:string){
 const response=await fetch('https://api.razorpay.com/v1'+path,{headers:{authorization:'Basic '+btoa(env('RAZORPAY_LIVE_KEY_ID')+':'+env('RAZORPAY_LIVE_KEY_SECRET'))}});
 if(!response.ok)throw Error('Gateway verification failed: '+response.status);
 return response.json();
}
Deno.serve(async req=>{
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 if(env('SUPABASE_URL').replace(/\/$/,'')!=='https://mepulcdlighuiwgbutnx.supabase.co'||env('RAZORPAY_LIVE_ENABLED')!=='true'||!env('RAZORPAY_LIVE_KEY_ID').startsWith('rzp_live_')||!env('RAZORPAY_LIVE_WEBHOOK_SECRET')||!env('RAZORPAY_LIVE_KEY_SECRET'))return json({error:'Live webhook disabled'},503);
 const raw=await req.text();
 if(raw.length>1024*1024)return json({error:'Payload too large'},413);
 if(!equal(await signature(env('RAZORPAY_LIVE_WEBHOOK_SECRET'),raw),req.headers.get('x-razorpay-signature')??''))return json({error:'Invalid signature'},401);
 let event:any;try{event=JSON.parse(raw)}catch{return json({error:'Bad JSON'},400)}
 if(!['payment.captured','payment.failed','refund.processed'].includes(event.event))return json({received:true,ignored:true});
 try{
  const url=env('SUPABASE_URL'),key=env('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!key)throw Error('Test DB configuration missing');
  const db=createClient(url,key,{auth:{persistSession:false}});
  if(event.event==='refund.processed'){
   const entity=event.payload?.refund?.entity;
   if(typeof entity?.id!=='string'||typeof entity?.payment_id!=='string')return json({received:true,skipped:true});
   const refund=await gateway('/refunds/'+encodeURIComponent(entity.id));
   if(refund.status!=='processed')return json({received:true,notProcessed:true});
   if(refund.id!==entity.id||refund.payment_id!==entity.payment_id||!Number.isSafeInteger(refund.amount)||refund.amount<=0)throw Error('Refund reference mismatch');
   const payment=await gateway('/payments/'+encodeURIComponent(refund.payment_id));
   if(payment.status!=='refunded'&&payment.status!=='captured')throw Error('Refund payment state mismatch');
   if(typeof payment.order_id!=='string'||payment.currency!=='INR')throw Error('Invalid refund payment');
   const {data:order,error:lookupErr}=await db.from('spotmate_recharge_orders').select('id,provider_order_id,provider_payment_id,amount_paise,currency').eq('provider_order_id',payment.order_id).eq('provider','razorpay_live').maybeSingle();
   if(lookupErr)throw lookupErr;
   if(!order)return json({received:true,unmatched:true});
   if(order.provider_payment_id!==payment.id||order.currency!=='INR'||payment.amount!==order.amount_paise||refund.amount>order.amount_paise)throw Error('Refund/order mismatch');
   const {data:outcome,error:rpcErr}=await db.rpc('spotmate_record_refund_live',{p_provider_refund_id:refund.id,p_provider_payment_id:refund.payment_id,p_amount_paise:refund.amount});
   if(rpcErr)throw rpcErr;
   return json({received:true,refund:outcome});
  }
  const entity=event.payload?.payment?.entity;
  if(typeof entity?.id!=='string'||typeof entity?.order_id!=='string')return json({received:true,skipped:true});
  const payment=await gateway('/payments/'+encodeURIComponent(entity.id));
  if(payment.id!==entity.id||payment.order_id!==entity.order_id)throw Error('Payment reference mismatch');
  if(event.event==='payment.failed'){
   if(payment.status!=='failed')return json({received:true,notFailed:true});
   const {error}=await db.rpc('spotmate_record_failed_payment_live',{p_provider_order_id:payment.order_id,p_provider_payment_id:payment.id});
   if(error)throw error;
   return json({received:true,failed:true});
  }
  if(payment.status!=='captured')return json({received:true,notCaptured:true});
  const {data:order,error}=await db.from('spotmate_recharge_orders').select('id,amount_paise,currency,status,provider,provider_order_id,provider_payment_id').eq('provider_order_id',payment.order_id).eq('provider','razorpay_live').maybeSingle();
  if(error)throw error;
  if(!order)return json({received:true,unmatched:true});
  if(order.status==='refunded')return json({received:true,alreadyRefunded:true});
  if(order.status==='paid')return json({received:true,alreadyCredited:true});
  if(!['pending','failed'].includes(order.status)||payment.amount!==order.amount_paise||payment.currency!=='INR'||order.currency!=='INR')throw Error('Order/payment mismatch');
  const {error:rpcError}=await db.rpc('spotmate_settle_razorpay_live',{p_order_id:order.id,p_provider_order_id:order.provider_order_id,p_amount_paise:order.amount_paise,p_provider_payment_id:payment.id});
  if(rpcError)throw rpcError;
  return json({received:true});
 }catch(e){console.error('Live webhook failed',e instanceof Error?e.message:'unknown');return json({error:'Webhook retry required'},500)}
});