import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import {createClient} from 'npm:@supabase/supabase-js@2.81.1';
const cors={'access-control-allow-origin':'*','access-control-allow-methods':'POST, OPTIONS','access-control-allow-headers':'authorization, apikey, content-type, x-client-info'};
const json=(o:unknown,status=200)=>new Response(JSON.stringify(o),{status,headers:{...cors,'content-type':'application/json','cache-control':'no-store'}});
const cfg=(x:string)=>Deno.env.get(x)??'';
const enc=new TextEncoder();
const expectedUrl='https://mepulcdlighuiwgbutnx.supabase.co';
const liveCatalog:Record<string,{credits:number;amount:number}>={starter:{credits:100,amount:4900},social:{credits:250,amount:9900},plus:{credits:600,amount:19900}};
const isolated=()=>cfg('SUPABASE_URL').replace(/\/$/,'')===expectedUrl;
const credentials=()=>{const id=cfg('RAZORPAY_LIVE_KEY_ID'),secret=cfg('RAZORPAY_LIVE_KEY_SECRET');if(cfg('RAZORPAY_LIVE_ENABLED')!=='true'|| !id.startsWith('rzp_live_')|| !secret)throw Error('Live payments disabled');return {id,secret}};
async function gateway(path:string,init:RequestInit={}){const c=credentials(),response=await fetch('https://api.razorpay.com/v1'+path,{...init,headers:{Authorization:'Basic '+btoa(c.id+':'+c.secret),'content-type':'application/json',...init.headers}});if(!response.ok)throw Error('Razorpay API '+response.status);return response.json();}
async function hmac(secret:string,message:string){const key=await crypto.subtle.importKey('raw',enc.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,enc.encode(message)))].map(x=>x.toString(16).padStart(2,'0')).join('')}
function equals(a:string,b:string){if(!/^[0-9a-f]{64}$/i.test(a)|| !/^[0-9a-f]{64}$/i.test(b))return false;let d=0;for(let i=0;i<64;i++)d|=a.toLowerCase().charCodeAt(i)^b.toLowerCase().charCodeAt(i);return d===0;}
async function settle(db:any,order:any,paymentId?:string){
 if(order.status==='paid')return {status:'paid',credited:false};
 if(!['pending','failed'].includes(order.status))return {status:order.status,credited:false};
 let payment:any;
 if(paymentId)payment=await gateway('/payments/'+encodeURIComponent(paymentId));
 else {const all=await gateway('/orders/'+encodeURIComponent(order.provider_order_id)+'/payments');payment=all.items?.find((p:any)=>p.status==='captured'&&p.order_id===order.provider_order_id&&p.amount===order.amount_paise&&p.currency==='INR');if(!payment){const failure=all.items?.find((p:any)=>p.status==='failed'&&p.order_id===order.provider_order_id&&p.amount===order.amount_paise&&p.currency==='INR'&&typeof p.id==='string');if(failure){const {error}=await db.rpc('spotmate_record_failed_payment_live',{p_provider_order_id:failure.order_id,p_provider_payment_id:failure.id});if(error)throw error;return {status:'failed',credited:false};}}}
 if(!payment || payment.status!=='captured')return {status:'pending',credited:false};
 if(payment.order_id!==order.provider_order_id||payment.amount!==order.amount_paise||payment.currency!=='INR'||typeof payment.id!=='string')throw Error('Payment does not match order');
 const {data,error}=await db.rpc('spotmate_settle_razorpay_live',{p_order_id:order.id,p_provider_order_id:order.provider_order_id,p_amount_paise:order.amount_paise,p_provider_payment_id:payment.id});
 if(error)throw error;
 return {status:'paid',credited:data===true};
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 try{credentials();if(!isolated())throw Error('Wrong environment')}catch{return json({error:'Live checkout disabled'},503)}
 const auth=req.headers.get('authorization')??'';
 if(!auth.startsWith('Bearer '))return json({error:'Authentication required'},401);
 const url=cfg('SUPABASE_URL'),anon=cfg('SUPABASE_ANON_KEY'),role=cfg('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!anon||!role)return json({error:'Backend not configured'},503);
 const userClient=createClient(url,anon,{auth:{persistSession:false}});
 const {data:{user},error:authError}=await userClient.auth.getUser(auth.slice(7));
 if(authError||!user)return json({error:'Unauthorized'},401);
 const db=createClient(url,role,{auth:{persistSession:false}});
 let input:Record<string,unknown>;try{input=await req.json()}catch{return json({error:'Invalid JSON'},400)}
 try{
  if(input.action==='create'){
   if(typeof input.packageId!=='string'||!Object.prototype.hasOwnProperty.call(liveCatalog,input.packageId))return json({error:'Invalid package'},400);
   const {data:pack,error}=await db.from('spotmate_credit_packages').select('id,credits,price_paise,currency,active').eq('id',input.packageId).single();
   if(error||!pack||pack.active!==true||pack.currency!=='INR'||pack.credits!==liveCatalog[input.packageId].credits||pack.price_paise!==liveCatalog[input.packageId].amount||pack.id!==input.packageId)return json({error:'Invalid package'},400);
   const external=await gateway('/orders',{method:'POST',body:JSON.stringify({amount:pack.price_paise,currency:'INR',receipt:'SM'+crypto.randomUUID().replaceAll('-','').slice(0,26),notes:{package_id:pack.id,spotmate_live:'true'}})});
   if(external.amount!==pack.price_paise||external.currency!=='INR'||typeof external.id!=='string')throw Error('Invalid gateway order');
   const {data:created,error:saveError}=await db.from('spotmate_recharge_orders').insert({user_id:user.id,package_id:pack.id,amount_paise:pack.price_paise,credits:pack.credits,currency:'INR',provider:'razorpay_live',provider_order_id:external.id,status:'pending'}).select('id').single();
   if(saveError)throw saveError;
   return json({orderId:created.id,providerOrderId:external.id,amount:pack.price_paise,currency:'INR',keyId:credentials().id,credits:pack.credits});
  }
  if(input.action==='verify'||input.action==='check'){
   if(typeof input.orderId!=='string'||!/^[0-9a-f-]{36}$/i.test(input.orderId))return json({error:'Invalid order ID'},400);
   const {data:order,error}=await db.from('spotmate_recharge_orders').select('id,user_id,amount_paise,currency,status,provider,provider_order_id').eq('id',input.orderId).eq('user_id',user.id).single();
   if(error||!order||order.provider!=='razorpay_live')return json({error:'Order not found'},404);
   if(input.action==='verify'){
    if(typeof input.paymentId!=='string'||typeof input.signature!=='string'||typeof input.providerOrderId!=='string'||input.providerOrderId!==order.provider_order_id)return json({error:'Invalid callback'},400);
    if(!equals(await hmac(credentials().secret,order.provider_order_id+'|'+input.paymentId),input.signature))return json({error:'Invalid payment signature'},403);
    return json(await settle(db,order,input.paymentId));
   }
   return json(await settle(db,order));
  }
  return json({error:'Unsupported action'},400);
 }catch(e){console.error('Live checkout failed',e instanceof Error?e.message:'unknown');return json({error:'Unable to complete payment request'},502)}
});