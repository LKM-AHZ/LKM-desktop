import assert from 'node:assert/strict';
import {loadArkTs} from './ohos-test-loader.mjs';
let handler; class MethodChannel{setMethodCallHandler(value){handler=value;}}
let request;let gate;let failure=false;
const fido2={ClientCapability:{PASSKEY_PLATFORM_AUTHENTICATOR:'passkey',USER_VERIFYING_PLATFORM_AUTHENTICATOR:'uv'},
 getClientCapabilities:async()=>new Map([['passkey',true],['uv',true]]),
 register:async(_,options)=>{request=options;if(gate)await gate;if(failure)throw {code:801,message:'unsupported'};return {registrationResponseJson:{id:'credential',rawId:'credential',response:{clientDataJson:'client',attestationObject:'attestation',transports:['internal']}}};},
 authenticate:async(_,options)=>{request=options;return {authenticationResponseJson:{id:'credential',rawId:'credential',response:{clientDataJson:'client',authenticatorData:'auth',signature:'signature',userHandle:'user'}}};},
};
const Plugin=loadArkTs(new URL('../packages/passkeys/ohos/src/main/ets/PasskeysOhosPlugin.ets',import.meta.url),new Map([
 ['@ohos/flutter_ohos',{MethodChannel}],['@kit.OnlineAuthenticationKit',{fido2}],
])).default;
const plugin=new Plugin();plugin.onAttachedToEngine({getBinaryMessenger:()=>({})});plugin.onAttachedToAbility({getAbility:()=>({context:{}})});
const invoke=(method,args={})=>new Promise(resolve=>plugin.onMethodCall({method,argument:key=>args[key]??null},{success:value=>resolve({value}),error:(code,message)=>resolve({code,message}),notImplemented:()=>resolve({notImplemented:true})}));
assert.equal((await invoke('availability')).value.get('passkeys'),true);
assert.equal((await invoke('cancel')).value,null);
const challenge=new Uint8Array(32).fill(42);
const credential=new Map([['id',new Uint8Array([1,2,3])],['type','public-key'],['transports',['internal']]]);
const registration={challenge,rp:new Map([['id','example.org'],['name','Example']]),user:new Map([['id',new Uint8Array([4])],['name','user'],['displayName','User']]),
 pubKeyCredParams:[new Map([['type','public-key'],['alg',-7]])],excludeCredentials:[credential],timeout:20000,
 authenticatorSelection:new Map([['residentKey','required'],['userVerification','required']]),attestation:'none'};
let result=await invoke('register',registration);assert.equal(JSON.parse(result.value).response.attestationObject,'attestation');
assert.deepEqual(Array.from(request.publicKey.challenge),Array.from(challenge));assert.equal(request.publicKey.rp.id,'example.org');
assert.equal(request.publicKey.user.name,'user');assert.equal(request.publicKey.pubKeyCredParams[0].alg,-7);
assert.equal(request.publicKey.authenticatorSelection.userVerification,'required');assert.equal(request.publicKey.excludeCredentials[0].type,'public-key');
result=await invoke('authenticate',{challenge,rpId:'example.org',allowCredentials:[credential],userVerification:'required'});
assert.equal(JSON.parse(result.value).response.signature,'signature');assert.equal(request.publicKey.rpId,'example.org');assert.equal(request.publicKey.userVerification,'required');
assert.match((await invoke('register',{...registration,challenge:new Uint8Array()})).message,/Empty/);
failure=true;assert.equal((await invoke('register',registration)).code,'deviceNotSupported');failure=false;
let release;gate=new Promise(resolve=>release=resolve);const pending=invoke('register',registration);await new Promise(resolve=>setImmediate(resolve));
assert.equal((await invoke('cancel')).code,'operation_active');assert.equal((await invoke('authenticate',{challenge})).code,'operation_active');
plugin.onDetachedFromAbility();assert.match((await pending).message,/detached/);release();await new Promise(resolve=>setImmediate(resolve));
plugin.onDetachedFromEngine({});assert.equal(handler,null);
console.log('OHOS passkeys: real FIDO2 request fields/bytes, capabilities, responses, failures, overlap/cancel honesty and stale-detach protection passed.');
