import { AbilityAware, AbilityPluginBinding, FlutterPlugin, FlutterPluginBinding,
  MethodCallHandler, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import { fido2 } from '@kit.OnlineAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export default class PasskeysOhosPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private pending: MethodResult | null = null;
  getUniqueClassName(): string { return 'PasskeysOhosPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(),'lkm.passkeys/ohos');this.channel.setMethodCallHandler(this);
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void { this.context=binding.getAbility().context; }
  onDetachedFromAbility(): void {
    this.context=null;
    const pending=this.pending;this.pending=null;
    pending?.error('passkey_error','Passkey ability detached',null);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.onDetachedFromAbility();this.channel?.setMethodCallHandler(null);this.channel=null;
  }
  onMethodCall(call: MethodCall,result: MethodResult): void {
    if(call.method==='cancel') {
      // The SDK has no cancellation API: never claim an active system sheet was dismissed.
      if(this.pending!==null) result.error('operation_active','Complete or dismiss the active system prompt',null);
      else result.success(null);
      return;
    }
    if(!['availability','register','authenticate'].includes(call.method)) {result.notImplemented();return;}
    if(this.pending!==null) {result.error('operation_active','Another passkey operation is active',null);return;}
    const context=this.context;
    if(context===null) {result.error('passkey_error','Passkey ability missing',null);return;}
    this.pending=result;
    this.run(call,context).then((value:Object)=>{
      if(this.pending!==result)return;this.pending=null;result.success(value);
    }).catch((error:BusinessError)=>{
      if(this.pending!==result)return;this.pending=null;
      const code = [1021300004,1021300010].includes(error.code) ? 'cancelled' :
        [801,1021300001].includes(error.code) ? 'deviceNotSupported' : 'passkey_error';
      result.error(code,error.message,error.code??null);
    });
  }
  private credentials(call:MethodCall,key:string):fido2.PublicKeyCredentialDescriptor[] {
    const entries=(call.argument(key)??[]) as Map<string,Object>[];
    return entries.map((entry:Map<string,Object>):fido2.PublicKeyCredentialDescriptor=>({
      id:entry.get('id') as Uint8Array,type:entry.get('type') as fido2.PublicKeyCredentialType,
      transports:entry.get('transports') as fido2.AuthenticatorTransport[],
    }));
  }
  private async run(call:MethodCall,context:common.UIAbilityContext):Promise<Object> {
    if(call.method==='availability') {
      let capabilities: Map<fido2.ClientCapability,boolean>;
      try { capabilities=await fido2.getClientCapabilities(context); }
      catch(error) {
        if([801,1021300001].includes((error as BusinessError).code)) return new Map<string,boolean>([['passkeys',false],['userVerification',false]]);
        throw error as Error;
      }
      return new Map<string,boolean>([
        ['passkeys',capabilities.get(fido2.ClientCapability.PASSKEY_PLATFORM_AUTHENTICATOR)??false],
        ['userVerification',capabilities.get(fido2.ClientCapability.USER_VERIFYING_PLATFORM_AUTHENTICATOR)??false],
      ]);
    }
    const challenge=call.argument('challenge') as Uint8Array;
    if(challenge.byteLength===0)throw new Error('Empty passkey challenge');
    if(call.method==='register') {
      const rp=call.argument('rp') as Map<string,Object>;
      const user=call.argument('user') as Map<string,Object>;
      const params=call.argument('pubKeyCredParams') as Map<string,Object>[];
      const options:fido2.PublicKeyCredentialCreationOptions={
        challenge,rp:{id:rp.get('id') as string,name:rp.get('name') as string},
        user:{id:user.get('id') as Uint8Array,name:user.get('name') as string,displayName:user.get('displayName') as string},
        pubKeyCredParams:params.map((p:Map<string,Object>):fido2.PublicKeyCredentialParameters=>({type:p.get('type') as fido2.PublicKeyCredentialType,alg:p.get('alg') as fido2.Algorithm})),
        excludeCredentials:this.credentials(call,'excludeCredentials'),
      };
      const timeout=call.argument('timeout') as number;if(timeout!=null)options.timeout=timeout;
      const attestation=call.argument('attestation') as fido2.AttestationConveyancePreference;if(attestation!=null)options.attestation=attestation;
      const selection=call.argument('authenticatorSelection') as Map<string,Object>;
      if(selection!=null) {
        const criteria:fido2.AuthenticatorSelectionCriteria={};
        if(selection.has('authenticatorAttachment'))criteria.authenticatorAttachment=selection.get('authenticatorAttachment') as fido2.AuthenticatorAttachment;
        if(selection.has('residentKey'))criteria.residentKey=selection.get('residentKey') as fido2.ResidentKeyRequirement;
        if(selection.has('requireResidentKey'))criteria.requireResidentKey=selection.get('requireResidentKey') as boolean;
        if(selection.has('userVerification'))criteria.userVerification=selection.get('userVerification') as fido2.UserVerificationRequirement;
        options.authenticatorSelection=criteria;
      }
      const response=await fido2.register(context,{publicKey:options});
      return JSON.stringify(response.registrationResponseJson);
    }
    const options:fido2.PublicKeyCredentialRequestOptions={challenge,rpId:call.argument('rpId') as string,
      allowCredentials:this.credentials(call,'allowCredentials')};
    const timeout=call.argument('timeout') as number;if(timeout!=null)options.timeout=timeout;
    const verification=call.argument('userVerification') as fido2.UserVerificationRequirement;if(verification!=null)options.userVerification=verification;
    const response=await fido2.authenticate(context,{publicKey:options});
    return JSON.stringify(response.authenticationResponseJson);
  }
}
