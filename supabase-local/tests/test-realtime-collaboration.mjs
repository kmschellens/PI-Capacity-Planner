import fs from 'node:fs';
import crypto from 'node:crypto';
import vm from 'node:vm';

const projectRoot=new URL('../../',import.meta.url);
const html=fs.readFileSync(new URL('index.html',projectRoot),'utf8');
const env=fs.readFileSync(new URL('supabase-local/.env',projectRoot),'utf8');
const anonKey=html.match(/const SUPABASE_ANON_KEY='([^']+)'/)?.[1];
const serviceKey=env.match(/^SERVICE_ROLE_KEY=(.+)$/m)?.[1];
const baseUrl='http://localhost:8000';
if(!anonKey||!serviceKey)throw new Error('Could not read local Supabase keys.');

const runId=Date.now().toString(36)+crypto.randomBytes(3).toString('hex');
const password=`Realtime-${crypto.randomUUID()}!`;
const users=[];
let boardId=null;

async function request(path,{token=anonKey,method='GET',body,prefer}={}){
  const response=await fetch(baseUrl+path,{method,headers:{apikey:anonKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json',...(prefer?{Prefer:prefer}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  const text=await response.text();
  const data=text?JSON.parse(text):null;
  if(!response.ok)throw new Error(`${method} ${path} failed (${response.status}): ${text}`);
  return data;
}

async function createUser(label){
  const email=`collab-${label}-${runId}@example.test`;
  const data=await request('/auth/v1/signup',{method:'POST',body:{email,password}});
  if(!data?.access_token||!data?.user?.id)throw new Error(`No session returned for ${label}.`);
  const user={label,email,id:data.user.id,token:data.access_token};users.push(user);return user;
}

async function loadSupabaseClient(){
  const response=await fetch('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.108.2');
  if(!response.ok)throw new Error(`Could not load supabase-js (${response.status}).`);
  globalThis.self=globalThis;
  vm.runInThisContext(await response.text(),{filename:'supabase-js-2.108.2.js'});
  if(!globalThis.supabase?.createClient)throw new Error('supabase-js bundle did not expose createClient.');
  return globalThis.supabase.createClient;
}

function subscribe(channel,{expectError=false,label='channel'}={}){
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error(`Timed out subscribing ${label}.`)),7000);
    channel.subscribe((status,error)=>{
      if(status==='SUBSCRIBED'&&!expectError){clearTimeout(timer);resolve();}
      if(status==='CHANNEL_ERROR'){
        clearTimeout(timer);
        if(expectError)resolve(error);else reject(error||new Error(`${label} was rejected.`));
      }
      if((status==='TIMED_OUT'||status==='CLOSED')&&!expectError){clearTimeout(timer);reject(error||new Error(`${label} ${status.toLowerCase()}.`));}
    });
  });
}

function waitForPresence(channel,clientId,label){
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error(`Timed out waiting for ${label}.`)),7000);
    channel.on('presence',{event:'sync'},()=>{
      if(JSON.stringify(channel.presenceState()).includes(clientId)){clearTimeout(timer);resolve();}
    });
  });
}

function waitForCursor(channel){
  return new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>reject(new Error('Timed out waiting for cursor Broadcast.')),7000);
    channel.on('broadcast',{event:'cursor'},message=>{clearTimeout(timer);resolve(message.payload);});
  });
}

async function deleteTestData(owner){
  if(boardId&&owner?.token)await request(`/rest/v1/boards?id=eq.${boardId}`,{token:owner.token,method:'DELETE'}).catch(()=>{});
  await Promise.all(users.map(user=>fetch(`${baseUrl}/auth/v1/admin/users/${user.id}`,{method:'DELETE',headers:{apikey:serviceKey,Authorization:`Bearer ${serviceKey}`}})));
}

let owner,writer,outsider,ownerClient,writerClient,outsiderClient,ownerChannel,writerChannel,outsiderChannel;
try{
  owner=await createUser('owner');writer=await createUser('writer');outsider=await createUser('outsider');
  const boards=await request('/rest/v1/boards',{token:owner.token,method:'POST',prefer:'return=representation',body:{name:`Realtime test ${runId}`,state:{version:6,tabs:[],tabIdSeq:0,boardState:{}}}});
  boardId=boards?.[0]?.id;if(!boardId)throw new Error('Test board was not created.');
  if(boards[0].user_id!==owner.id)throw new Error(`Board owner mismatch: ${boards[0].user_id} !== ${owner.id}`);
  const permission=await request('/rest/v1/rpc/board_access_permission',{token:owner.token,method:'POST',body:{check_board_id:boardId}});
  if(permission!=='owner')throw new Error(`Owner permission RPC returned ${JSON.stringify(permission)}.`);
  await request('/rest/v1/board_collaborators',{token:owner.token,method:'POST',body:{board_id:boardId,user_email:writer.email,permission:'write'}});

  const createClient=await loadSupabaseClient(),clientOptions={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
  ownerClient=createClient(baseUrl,anonKey,clientOptions);writerClient=createClient(baseUrl,anonKey,clientOptions);outsiderClient=createClient(baseUrl,anonKey,clientOptions);
  await Promise.all([ownerClient.realtime.setAuth(owner.token),writerClient.realtime.setAuth(writer.token),outsiderClient.realtime.setAuth(outsider.token)]);
  const channelOptions=clientId=>({config:{private:true,presence:{key:clientId},broadcast:{self:false,ack:true}}});
  ownerChannel=ownerClient.channel(`board:${boardId}`,channelOptions('owner-client'));
  writerChannel=writerClient.channel(`board:${boardId}`,channelOptions('writer-client'));
  outsiderChannel=outsiderClient.channel(`board:${boardId}`,channelOptions('outsider-client'));
  const ownerSeesWriter=waitForPresence(ownerChannel,'writer-client','writer presence on owner channel');
  const writerSeesOwner=waitForPresence(writerChannel,'owner-client','owner presence on writer channel');
  const cursorReceived=waitForCursor(writerChannel);
  await subscribe(ownerChannel,{label:'owner channel'});
  await ownerChannel.track({clientId:'owner-client',userId:owner.id,email:owner.email,name:'owner',location:'capacity:1'});
  await subscribe(writerChannel,{label:'writer channel'});
  await writerChannel.track({clientId:'writer-client',userId:writer.id,email:writer.email,name:'writer',location:'capacity:1'});
  await Promise.all([ownerSeesWriter,writerSeesOwner]);

  const cursor={clientId:'owner-client',userId:owner.id,name:'owner',location:'capacity:1',x:.25,y:.75};
  await ownerChannel.send({type:'broadcast',event:'cursor',payload:cursor});
  const broadcast=await cursorReceived;
  if(broadcast?.x!==cursor.x||broadcast?.y!==cursor.y)throw new Error('Cursor payload changed in transit.');

  await subscribe(outsiderChannel,{expectError:true,label:'outsider channel'});
  console.log('Realtime collaboration OK: Presence + cursor Broadcast + unauthorized join rejected.');
}finally{
  await Promise.all([
    ownerChannel&&ownerClient?.removeChannel(ownerChannel),
    writerChannel&&writerClient?.removeChannel(writerChannel),
    outsiderChannel&&outsiderClient?.removeChannel(outsiderChannel)
  ].filter(Boolean)).catch(()=>{});
  ownerClient?.realtime.disconnect();writerClient?.realtime.disconnect();outsiderClient?.realtime.disconnect();
  await deleteTestData(owner);
}
