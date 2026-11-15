/*
 * Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  EventChannel,
  EventSink,
  AbilityAware,
  AbilityPluginBinding
} from '@ohos/flutter_ohos';
import { tag } from '@kit.ConnectivityKit';
import { UIAbility, Want, AbilityConstant, bundleManager, ApplicationStateChangeCallback, common } from '@kit.AbilityKit';
import { nfcController } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AsyncCallback } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import json from '@ohos.util.json';


/** MIFARE Classic认证信息缓存结构 **/
class MifareAuthInfo {
  keyA: number[] | null = null;
  keyB: number[] | null = null;
  lastUsedKey: string | null = null; // 记录最后成功认证使用的密钥类型 'A' 或 'B'
}

/** NFC标签ElementName初始化结构 **/
class NfcTagElementName implements bundleManager.ElementName {
  bundleName: string = '';
  abilityName: string = '';
  moduleName: string = '';
}

/** NFC会话状态枚举 —— 状态机驱动的生命周期管理 */
enum NfcSessionState {
  IDLE,           // 空闲：所有状态已清理，可接受poll调用
  POLLING,        // 轮询中：readerMode已注册，等待标签到达
  TAG_CONNECTED,  // 标签已连接：TagInfo已设置，可接受操作调用
  OPERATING,      // 操作中：正在执行NDEF/MIFARE/transceive操作
  CLEANUP         // 清理中：正在执行统一清理，完成后回到IDLE
}

/** FlutterNfcKitPlugin **/
export default class FlutterNfcKitPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  // ===== 状态机核心 =====
  // 统一管理NFC会话生命周期，替代散布的isPollingActive/currentPollingResult/pollingTimeoutId等
  // 状态转换通过transitionTo()集中清理，消除碎片化
  private sessionState: NfcSessionState = NfcSessionState.IDLE;
  // 当前活跃的异步MethodResult集合（用于finish/超时时统一cancel）
  private pendingResults: Set<AsyncMethodResult> = new Set();
  // 轮询超时定时器ID（仅在POLLING状态下有效）
  private pollingTimeoutId: number | null = null;

  // ===== 标签数据 =====
  private TagInfo: tag.TagInfo | null = null;
  private ndefTechnology: tag.NdefTag | null = null;
  private mifareClassicTechnology: tag.MifareClassicTag | null = null;
  private mifareUltralightTechnology: tag.MifareUltralightTag | null = null;
  private mifareAuthCache: Map<number, MifareAuthInfo> = new Map();
  private tagTechnology: number[] = [];
  private lastTagUid: string | null = null;

  // ===== readerMode前台派发 =====
  private nfcTagElementName: bundleManager.ElementName | null = null;
  private readerModeCallback: AsyncCallback<tag.TagInfo> | null = null;
  private foregroundRegister: boolean = false;
  private tagFromForegroundDispatch: boolean = false;
  private registeredDiscTech: number[] | null = null;
  private isRegisteringOrUnregistering: boolean = false;

  // ===== 应用前后台 =====
  private isForeground: boolean = false;
  private backgroundUnregisterTimerId: number | null = null;
  // 后台延迟注销readerMode的时间（毫秒）
  // debounce机制：防止前后台快速切换时的注册/注销竞态
  // 值越大越安全（减少竞态概率），但后台NFC检测恢复延迟越长
  // 值越小响应越快，但快速前后台切换时可能出现注销/注册时序冲突
  // 推荐范围：300-800ms，默认500ms为平衡点
  private static readonly BACKGROUND_UNREGISTER_DELAY: number = 500;
  private appStateChangeCallback: ApplicationStateChangeCallback | null = null;

  // ===== Flutter通道 =====
  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  private isEventSinkReady: boolean = false;
  private pendingTagData: string | null = null;
  private ability: UIAbility | null = null;
  private nfcStateChangeCallback: ((state: nfcController.NfcState) => void) | null = null;


  /**
   * 处理NFC标签到达事件（后台分发场景）
   *
   * 注意：前台读卡（App在前台优先处理NFC标签）使用的是 tag.on('readerMode') 回调，
   * 标签信息通过 readerModeCallback 直接传递，不走 handleTag。
   *
   * 此方法仅用于后台分发场景：App不在前台时，系统通过 onCreate/onNewWant 将
   * 标签Want传递给Ability，Ability通过tag.getTagInfo(want)获取TagInfo后调用此方法。
   */
  public handleTag(tag: tag.TagInfo) {
    try {
      // 仅在readerMode正在轮询时忽略后台分发（避免前台轮询和后台Intent同时处理同一标签）
      // App在前台但不在轮询时（如通过NFC Intent跳转到前台的场景），仍需处理标签
      if (this.isForeground && this.sessionState === NfcSessionState.POLLING) {
        console.log('handleTag: App in foreground with active polling, ignoring background dispatch (readerMode will handle)');
        return;
      }

      // 检查标签是否有效
      if (!tag || !tag.technology || tag.technology.length === 0) {
        console.warn('Invalid tag received, skipping processing');
        return;
      }

      console.log('Processing background-dispatched tag with technologies:', tag.technology);
      console.log('Tag UID:', tag.uid);

      // 将真实NFC标签保存到this.TagInfo中
      this.TagInfo = tag;
      this.tagFromForegroundDispatch = true;

      // 如果正在进行轮询操作，立即触发标签检测处理
      if (this.sessionState === NfcSessionState.POLLING) {
        console.log('Tag detected during active polling, processing immediately');
        this.handleTagDetected(tag);
      } else {
        // 没有正在进行轮询，解析标签并通过EventChannel发送给Flutter层
        // EventSink未就绪时缓存数据，等就绪后自动发送
        console.log('Tag detected outside polling, sending to Flutter via EventChannel');

        try {
          let result = this.parseTag(tag);
          console.log('Auto-detected tag result:', result);

          if (this.eventSink && this.isEventSinkReady) {
            this.eventSink.success(result);
            console.log('Tag sent to Flutter layer via EventChannel');
          } else {
            // EventSink尚未就绪，缓存标签数据等待后续发送
            console.warn('EventSink not ready, caching tag data for later delivery');
            this.pendingTagData = result;
            this.retryPendingTagDelivery(3000);
          }
        } catch (parseError) {
          console.error('Error parsing auto-detected tag:', parseError);
        }
      }
    } catch (e) {
      console.error('Error handling tag:', e);
      // 发送错误信息给Flutter层
      if (this.eventSink) {
        this.eventSink.error('TAG_HANDLING_ERROR', 'Failed to handle tag', e);
      }
    }
  }

  constructor() {
  }

  // ===== 状态机核心方法 =====

  /**
   * 统一的状态转换方法 —— 所有状态变更的唯一入口
   * 集中处理状态变更前的清理工作，替代散布在5+个方法中的碎片化清理
   *
   * 状态转换矩阵:
   *   IDLE → POLLING: pollTag成功注册readerMode后
   *   POLLING → TAG_CONNECTED: handleTagDetected成功解析标签后
   *   POLLING → IDLE: 超时/poll失败后
   *   TAG_CONNECTED → OPERATING: 开始NDEF/MIFARE/transceive操作
   *   OPERATING → TAG_CONNECTED: 操作完成后
   *   TAG_CONNECTED → IDLE: finish后
   *   OPERATING → IDLE: finish/操作致命错误后
   *   任意 → IDLE: onDetachedFromAbility/onDetachedFromEngine后
   *
   * @param newState 目标状态
   * @param cancelPending 是否取消所有pending的异步MethodResult（finish/超时/detach时为true）
   */
  private transitionTo(newState: NfcSessionState, cancelPending: boolean = false): void {
    const oldState = this.sessionState;
    console.log(`NfcSession: transition ${NfcSessionState[oldState]} → ${NfcSessionState[newState]}${cancelPending ? ' (cancel pending)' : ''}`);

    // 取消所有pending的异步result（finish/超时/detach场景）
    if (cancelPending) {
      this.cancelAllPendingResults('Session transitioned to cleanup state');
    }

    // 根据目标状态执行不同的清理策略
    switch (newState) {
      case NfcSessionState.IDLE:
        // IDLE是最终清理状态：清空所有资源
        this.clearPollingState();
        this.clearTagState();
        this.unregisterReaderMode();
        this.clearNfcStateListener();
        break;

      case NfcSessionState.POLLING:
        // POLLING只清理旧的标签状态（保留readerMode注册）
        this.clearTagState();
        break;

      case NfcSessionState.TAG_CONNECTED:
        // TAG_CONNECTED：取消超时定时器（标签已到达不再需要超时）
        this.clearTimeout();
        break;

      case NfcSessionState.OPERATING:
        // OPERATING：不做额外清理，保持标签连接状态
        break;

      case NfcSessionState.CLEANUP:
        // CLEANUP是中间状态：执行全面清理后自动转到IDLE
        this.clearPollingState();
        this.clearTagState();
        this.unregisterReaderMode();
        this.clearNfcStateListener();
        // CLEANUP完成后自动转到IDLE
        this.sessionState = NfcSessionState.IDLE;
        console.log('NfcSession: cleanup completed, now IDLE');
        return; // 直接返回，不再设置下面的sessionState
    }

    this.sessionState = newState;
  }

  /** 取消所有pending的AsyncMethodResult */
  private cancelAllPendingResults(reason: string): void {
    if (this.pendingResults.size > 0) {
      console.log(`Cancelling ${this.pendingResults.size} pending AsyncMethodResults: ${reason}`);
      for (const ar of this.pendingResults) {
        ar.cancel(reason);
      }
      this.pendingResults.clear();
    }
  }

  /** 清理轮询相关状态（超时定时器、轮询标记、nfcState监听器） */
  private clearPollingState(): void {
    this.clearTimeout();
    this.tagFromForegroundDispatch = false;
    if (this.nfcStateChangeCallback) {
      try {
        nfcController.off('nfcStateChange', this.nfcStateChangeCallback);
      } catch (e) {
        console.warn('Failed to remove NFC state change listener:', e);
      }
      this.nfcStateChangeCallback = null;
    }
  }

  /** 清理超时定时器 */
  private clearTimeout(): void {
    if (this.pollingTimeoutId !== null) {
      clearTimeout(this.pollingTimeoutId);
      this.pollingTimeoutId = null;
      console.log('Polling timeout timer cancelled');
    }
  }

  /** 清理标签数据状态（TagInfo、技术对象缓存、认证缓存） */
  private clearTagState(): void {
    this.disconnectCachedTagTechnologies();
    this.TagInfo = null;
    this.tagTechnology = [];
    this.ndefTechnology = null;
    this.mifareClassicTechnology = null;
    this.mifareUltralightTechnology = null;
    this.mifareAuthCache.clear();
    this.lastTagUid = null;
  }

  /** 清理NFC系统状态监听器 */
  private clearNfcStateListener(): void {
    if (this.nfcStateChangeCallback) {
      try {
        nfcController.off('nfcStateChange', this.nfcStateChangeCallback);
      } catch (e) {
        console.warn('Failed to remove NFC state listener:', e);
      }
      this.nfcStateChangeCallback = null;
    }
  }

  /** 注册一个AsyncMethodResult到pending集合 */
  private registerPendingResult(ar: AsyncMethodResult): AsyncMethodResult {
    this.pendingResults.add(ar);
    // 当result被settled后自动从集合中移除（避免集合无限膨胀）
    const self = this;
    ar.setOnSettled(() => {
      self.pendingResults.delete(ar);
    });
    return ar;
  }

  /** 从pending集合中移除指定的result（手动移除，通常不需要，onSettled回调会自动移除） */
  private removePendingResult(ar: AsyncMethodResult): void {
    this.pendingResults.delete(ar);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
    console.log("FlutterNfcKitPlugin attached to ability");

    // 注册ApplicationContext生命周期监听（poll-only模式，与Android保持一致）
    // readerMode仅在poll时注册（类似Android的enableReaderMode），不在前台自动注册
    // 后台延迟注销readerMode（debounce机制防止前后台快速切换竞态），detach时注销
    // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#tagoffreadermode11
    try {
      if (this.ability) {
        this.appStateChangeCallback = {
          onApplicationForeground: () => {
            console.log('NFC plugin: App foreground detected via applicationStateChange');
            this.isForeground = true;
            // 前台时取消待执行的后台注销延迟（debounce机制的关键部分）
            // 如果App在延迟注销窗口内返回前台，取消注销保持readerMode注册状态
            if (this.backgroundUnregisterTimerId !== null) {
              clearTimeout(this.backgroundUnregisterTimerId);
              this.backgroundUnregisterTimerId = null;
              console.log('NFC plugin: cancelled pending background unregister on foreground');
            }
            // poll-only模式：readerMode不在前台自动注册，仅在poll()时注册（与Android一致）
          },
          onApplicationBackground: () => {
            console.log('NFC plugin: App background detected via applicationStateChange');
            this.isForeground = false;
            // 后台延迟注销readerMode（debounce机制：防止前后台快速切换时注册/注销竞态）
            // 如果App在延迟窗口内返回前台（如用户拉通知栏后立即返回），
            // foreground回调会取消此延迟，避免不必要的注销/重注册循环
            if (this.backgroundUnregisterTimerId !== null) {
              clearTimeout(this.backgroundUnregisterTimerId);
              this.backgroundUnregisterTimerId = null;
            }
            this.backgroundUnregisterTimerId = setTimeout(() => {
              console.log('NFC plugin: executing delayed background readerMode unregister');
              this.unregisterReaderMode();
              this.backgroundUnregisterTimerId = null;
            }, FlutterNfcKitPlugin.BACKGROUND_UNREGISTER_DELAY);
            console.log(`NFC plugin: background unregister delayed for ${FlutterNfcKitPlugin.BACKGROUND_UNREGISTER_DELAY}ms`);
          }
        };

        const applicationContext = this.ability.context.getApplicationContext();
        applicationContext.on('applicationStateChange', this.appStateChangeCallback);
        console.log('NFC plugin: applicationStateChange listener registered (poll-only mode, same as Android)');

        if (!this.nfcTagElementName) {
          console.warn('ElementName not initialized from Want yet, attempting fallback initialization from Ability context');
          this.tryInitElementNameFromAbilityContext();
        } else {
          console.log(`ElementName already initialized: bundle=${this.nfcTagElementName.bundleName}, ability=${this.nfcTagElementName.abilityName}`);
        }

        // 同步当前App前台状态（applicationStateChange只在状态变化时回调，不报告当前状态）
        // 如果App已在前台（冷启动或热恢复），需要主动设置isForeground=true
        // 避免初始状态下isForeground=false导致后台Intent被误处理
        // 鸿蒙没有直接查询App当前前台/后台状态的API，
        // 但onAttachedToAbility通常在App前台时调用（Flutter引擎初始化时App已可见），
        // 因此默认设置isForeground=true
        this.isForeground = true;
        console.log('NFC plugin: isForeground initialized to true (onAttachedToAbility usually called when app is visible)');
      }
    } catch (e) {
      console.error('Error in onAttachedToAbility:', e);
    }
  }

  /**
   * 从Want初始化ElementName（官方推荐方式）
   * 在EntryAbility.onCreate(want)中调用此方法
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/nfc-tag-access-guide
   */
  public initElementNameFromWant(want: Want): void {
    try {
      const elementName = new NfcTagElementName();
      elementName.bundleName = want.bundleName ?? '';
      elementName.abilityName = want.abilityName ?? '';
      elementName.moduleName = want.moduleName ?? '';
      this.nfcTagElementName = elementName;
      console.log(`ElementName initialized from want: bundle=${this.nfcTagElementName.bundleName}, ability=${this.nfcTagElementName.abilityName}`);
    } catch (e) {
      console.error('Error initializing ElementName from want:', e);
    }
  }

  /**
   * 从Ability context回退初始化ElementName
   *
   * 当EntryAbility未通过Want传递ElementName时（如冷启动无NFC Intent场景），
   * 从Ability的context属性中提取bundleName/abilityName/moduleName作为回退。
   * 这种方式初始化的ElementName可能不如Want方式精确（moduleName可能缺失），
   * 但足以满足tag.on('readerMode')的注册要求。
   *
   * 调用时机：
   * 1. onAttachedToAbility中，如果Want尚未初始化ElementName
   * 2. registerReaderMode中，如果nfcTagElementName仍为null
   */
  private tryInitElementNameFromAbilityContext(): void {
    if (this.nfcTagElementName != null) {
      console.log('tryInitElementNameFromAbilityContext: ElementName already initialized, skipping fallback');
      return;
    }

    if (this.ability == null) {
      console.error('tryInitElementNameFromAbilityContext: ability is null, cannot fallback');
      return;
    }

    try {
      const context = this.ability.context;
      if (context == null) {
        console.error('tryInitElementNameFromAbilityContext: ability context is null');
        return;
      }

      const elementName = new NfcTagElementName();
      // 从AbilityContext提取信息构建ElementName
      // AbilityInfo 类型包含 bundleName、name (abilityName)、moduleName
      // ApplicationInfo 没有 bundleName 属性（ArkTS类型定义不包含）
      // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-abilityinfo
      if (context.abilityInfo) {
        elementName.bundleName = context.abilityInfo.bundleName ?? '';
        elementName.abilityName = context.abilityInfo.name ?? '';
        elementName.moduleName = context.abilityInfo.moduleName ?? '';
      }

      // 验证关键字段是否有效
      if (elementName.bundleName === '' && elementName.abilityName === '') {
        console.error('tryInitElementNameFromAbilityContext: extracted bundleName and abilityName are both empty, fallback failed');
        return;
      }

      this.nfcTagElementName = elementName;
      console.log(`ElementName initialized from Ability context fallback: bundle=${this.nfcTagElementName.bundleName}, ability=${this.nfcTagElementName.abilityName}, module=${this.nfcTagElementName.moduleName}`);
    } catch (e) {
      console.error('tryInitElementNameFromAbilityContext error:', e);
    }
  }

  /**
   * 注册前台读卡器模式 tag.on('readerMode')
   * 在pollTag()中调用（与Android的enableReaderMode一致），不在前台自动注册
   * 注销时机：finish/超时/后台/detach
   *
   * @param discTech 要检测的NFC技术类型列表，只支持基础通信技术（NFC_A/B/F/V）
   *   IsoDep/NDEF/MifareClassic/MifareUltralight等派生类型是标签被发现后
   *   在TagInfo.technology中附带的，在parseTag()中动态判断。
   *   参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#tagonreadermode11
   *
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/nfc-tag-access-guide
   */
  public registerReaderMode(discTech: number[]): void {
    // 防重入：如果正在注册/注销过程中，跳过本次调用避免时序混乱
    if (this.isRegisteringOrUnregistering) {
      console.warn('registerReaderMode: operation in progress, skipping to avoid timing conflict');
      return;
    }

    try {
      this.isRegisteringOrUnregistering = true;

      // 检查elementName是否已设置
      if (this.nfcTagElementName == null) {
        console.error('registerReaderMode: nfcTagElementName is null, cannot register');
        // 尝试从Ability context回退初始化ElementName（风险3修复）
        this.tryInitElementNameFromAbilityContext();
        if (this.nfcTagElementName == null) {
          this.isRegisteringOrUnregistering = false;
          return;
        }
        console.log('registerReaderMode: ElementName initialized from fallback, retrying registration');
      }

      // 如果已经注册，先取消再重新注册（Ability可能传入不同的discTech列表）
      if (this.foregroundRegister) {
        try {
          tag.off('readerMode', this.nfcTagElementName);
          console.log('registerReaderMode: previous registration cancelled');
        } catch (offError) {
          console.warn(`registerReaderMode: tag.off failed: ${offError}`);
          // off失败时重置注册状态，避免下次注册时误以为已注册而再次off
          this.foregroundRegister = false;
        }
      }

      // 定义readerMode回调
      this.readerModeCallback = (error: BusinessError, tagInfo: tag.TagInfo) => {
        try {
          if (error) {
            console.error(`readerMode callback error: ${error.code} - ${error.message}`);
            if (this.sessionState === NfcSessionState.POLLING) {
              this.handlePollingError('500', `readerMode error: ${error.message}`, `${error.code}`);
            }
            return;
          }

          // 验证标签有效性
          if (!tagInfo || !tagInfo.uid) {
            console.error('readerModeCb: tagInfo or uid is invalid');
            return;
          }
          if (!tagInfo.technology || tagInfo.technology.length === 0) {
            console.error('readerModeCb: technology is invalid');
            return;
          }

          console.log(`readerMode tag detected - UID: ${tagInfo.uid}, technologies: ${tagInfo.technology}`);
          this.TagInfo = tagInfo;
          this.tagFromForegroundDispatch = true;

          // readerMode仅在poll时注册，所以标签到达必然在poll期间
          if (this.sessionState === NfcSessionState.POLLING) {
            console.log('Tag detected via readerMode during active polling');
            this.handleTagDetected(tagInfo);
            return;
          }

          // 理论上不应出现此场景（readerMode只在poll时注册），安全兜底直接忽略
          console.warn('Tag detected via readerMode but no active poll - ignoring');
        } catch (callbackError) {
          console.error('Error in readerMode callback:', callbackError);
        }
      };

      // 注册前台读卡器模式
      tag.on('readerMode', this.nfcTagElementName, discTech, this.readerModeCallback);
      this.foregroundRegister = true;
      this.registeredDiscTech = discTech;
      console.log(`readerMode registered successfully - discTech: ${discTech}`);

    } catch (ex) {
      console.error(`registerReaderMode error: ${ex}`);
      // 注册失败时重置状态，避免下次调用时误判
      this.foregroundRegister = false;
    } finally {
      this.isRegisteringOrUnregistering = false;
    }
  }

  /**
   * 取消前台读卡器模式 tag.off('readerMode')
   * 在finish/超时/后台/detach时调用（与Android的disableReaderMode一致）
   * 官方文档要求：页面退出前台或页面销毁时调用off取消
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#tagoffreadermode11
   */
  public unregisterReaderMode(): void {
    // 防重入：如果正在注册过程中，跳过本次注销避免时序冲突
    if (this.isRegisteringOrUnregistering) {
      console.warn('unregisterReaderMode: registration operation in progress, skipping to avoid timing conflict');
      return;
    }

    try {
      this.isRegisteringOrUnregistering = true;

      if (this.foregroundRegister && this.nfcTagElementName != null) {
        try {
          tag.off('readerMode', this.nfcTagElementName);
          console.log('readerMode unregistered successfully');
        } catch (offError) {
          console.error(`unregisterReaderMode: tag.off failed: ${offError}`);
          // off失败后仍重置foregroundRegister，避免下次误判为已注册
          // 系统可能已在内部注销，或ElementName不匹配导致off失败
        }
      }
      this.foregroundRegister = false;
      this.tagFromForegroundDispatch = false;
      this.readerModeCallback = null;
      this.registeredDiscTech = null;
    } catch (ex) {
      console.error(`unregisterReaderMode error: ${ex}`);
      // 异常时仍重置所有状态，避免残留状态影响后续操作
      this.foregroundRegister = false;
      this.tagFromForegroundDispatch = false;
      this.readerModeCallback = null;
      this.registeredDiscTech = null;
    } finally {
      this.isRegisteringOrUnregistering = false;
    }
  }

  onDetachedFromAbility(): void {
    // 状态机统一清理：cancelPending=true 取消所有未完成的异步result
    console.log('onDetachedFromAbility: transitioning to IDLE with cancelPending');
    this.transitionTo(NfcSessionState.IDLE, true);

    // 取消ApplicationContext生命周期监听
    try {
      if (this.ability && this.appStateChangeCallback) {
        const applicationContext = this.ability.context.getApplicationContext();
        applicationContext.off('applicationStateChange', this.appStateChangeCallback);
        console.log('NFC plugin: applicationStateChange listener unregistered');
      }
    } catch (e) {
      console.error('Error unregistering applicationStateChange listener:', e);
    }
    this.appStateChangeCallback = null;
    this.isForeground = false;
    this.ability = null;

    console.log("FlutterNfcKitPlugin detached from ability and cleaned up");
  }

  getUniqueClassName(): string {
    return "FlutterNfcKitPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), "flutter_nfc_kit/method");
    this.methodChannel.setMethodCallHandler(this)
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "flutter_nfc_kit/event")

    // 修复EventSink设置的作用域问题
    const self = this;
    this.eventChannel.setStreamHandler({
      onListen(argument: ESObject, events: EventSink) {
        if (events != null) {
          self.eventSink = events;
          self.isEventSinkReady = true;
          console.log('EventSink initialized successfully');

          // 检查是否有缓存的NFC标签数据需要发送
          self.deliverPendingTagData();
        }
      },
      onCancel(args: ESObject) {
        self.eventSink = null;
        self.isEventSinkReady = false;
        console.log('EventSink cancelled');
      }
    })
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    // 状态机统一清理：cancelPending=true 取消所有未完成的异步result
    console.log('onDetachedFromEngine: transitioning to IDLE with cancelPending');
    this.transitionTo(NfcSessionState.IDLE, true);

    this.isEventSinkReady = false;
    this.pendingTagData = null;

    // 清理Flutter通道
    if (this.methodChannel != null) {
      this.methodChannel.setMethodCallHandler(null)
    }
    if (this.eventChannel != null) {
      this.eventChannel.setStreamHandler(null)
    }

    console.log("FlutterNfcKitPlugin detached from engine and cleaned up");
  }

  /**
   * 安全获取NFC标签技术对象
   * 避免在标签状态异常时强制获取
   */
  private safeGetTagTechnology<T>(tagInfo: tag.TagInfo, techType: number, getter: (info: tag.TagInfo) => T): T | null {
    try {
      // 检查技术类型是否支持
      if (!tagInfo.technology.includes(techType)) {
        return null;
      }

      // 尝试获取技术对象
      return getter(tagInfo);
    } catch (e) {
      console.error(`Error getting technology ${techType}:`, e);
      return null;
    }
  }

  parseTag(tagInfo: tag.TagInfo): string {
    // 检测标签更换：如果新标签的UID与上次不同，说明标签已更换
    // 需要在清理缓存前比较，因为清理缓存会删除旧TagInfo
    const newUid = this.arrayToHexString(tagInfo.uid);
    if (this.lastTagUid != null && this.lastTagUid !== newUid) {
      console.log(`Tag changed detected: old UID=${this.lastTagUid}, new UID=${newUid}`);
      // 标签更换时，缓存的标签技术对象和认证信息一定已失效（旧标签已不在场）
      // 主动断开旧标签技术对象的连接（释放资源，防止残留连接干扰新标签）
      this.disconnectCachedTagTechnologies();
      // 下面的清理逻辑会自动处理这些缓存
    }
    this.lastTagUid = newUid;

    this.TagInfo = tagInfo;

    // 不在开始就尝试获取NDEF技术，避免标签状态异常
    this.ndefTechnology = null;
    // 清理缓存的MIFARE标签技术对象
    this.mifareClassicTechnology = null;
    this.mifareUltralightTechnology = null;
    // 清理认证缓存
    this.mifareAuthCache.clear();

    this.tagTechnology = this.TagInfo.technology;

    // 通用字段
    let type: string = "unknown";
    let id: string = this.arrayToHexString(tagInfo.uid);
    let standard: string = "unknown";

    // ISO 14443 Type A
    let atqa: string = "";
    let sak: string = "";

    // ISO 14443 Type B
    let protocolInfo: string = "";
    let applicationData: string = "";

    // ISO 7816
    let historicalBytes: string = "";
    let hiLayerResponse: string = "";

    // NFC-F / Felica
    let manufacturer: string = "";
    let systemCode: string = "";

    // NFC-V
    let dsfId: string = "";

    // NDEF
    let ndefAvailable: boolean = false;
    let ndefWritable: boolean = false;
    let ndefCanMakeReadOnly: boolean = false;
    let ndefCapacity: number = 0;
    let ndefType: tag.NfcForumType | string = "";

    // Mifare 信息
    let mifareInfo: Record<string, ESObject> | null = null;

    try {
      // 检查支持的技术类型
      const techList = tagInfo.technology;
      // 验证技术列表有效性
      if (!techList || techList.length === 0) {
        console.warn('Tag has no supported technologies');
        throw new Error('No supported NFC technologies found');
      }

      // 尝试获取 NfcA 技术类型
      if (techList.includes(tag.NFC_A)) {
        const nfcATag = this.safeGetTagTechnology(tagInfo, tag.NFC_A, tag.getNfcA);
        if (nfcATag) {
          try {
            atqa = this.arrayToHexString(nfcATag.getAtqa());
            sak = this.byteToHexString(nfcATag.getSak());
            // 检查是否支持 ISO-DEP (ISO 14443-4)
            if (techList.includes(tag.ISO_DEP)) {
              standard = "ISO 14443-4 (Type A)";
              type = "iso7816";
              const isoDepTag = this.safeGetTagTechnology(tagInfo, tag.ISO_DEP, tag.getIsoDep);
              if (isoDepTag) {
                try {
                  const histBytes = isoDepTag.getHistoricalBytes();
                  if (histBytes) {
                    historicalBytes = this.arrayToHexString(histBytes);
                  }
                } catch (e) {
                  console.error("Error getting historical bytes:", e);
                }
              }
            }
            // 检查是否支持 MIFARE Classic
            else if (techList.includes(tag.MIFARE_CLASSIC)) {
              standard = "ISO 14443-3 (Type A)";
              type = "mifare_classic";
              const mifareClassicTag = this.safeGetTagTechnology(tagInfo, tag.MIFARE_CLASSIC, tag.getMifareClassic);
              // 缓存标签技术对象，供后续操作复用
              this.mifareClassicTechnology = mifareClassicTag;
              if (mifareClassicTag) {
                try {
                  const mifareType = mifareClassicTag.getType();
                  const tagSize = mifareClassicTag.getTagSize();
                  const sectorCount = mifareClassicTag.getSectorCount();

                  // 计算总块数
                  let totalBlockCount = 0;
                  for (let i = 0; i < sectorCount; i++) {
                    totalBlockCount += mifareClassicTag.getBlockCountInSector(i);
                  }

                  // 根据官方枚举类型和实际大小提供更详细的类型信息
                  let detailedType = this.getMifareClassicTypeString(mifareType);

                  mifareInfo = {
                    "type": detailedType,
                    "size": tagSize,
                    "blockSize": 16, // MIFARE Classic block size
                    "blockCount": totalBlockCount,
                    "sectorCount": sectorCount,
                    "isEmulated": mifareClassicTag.isEmulatedTag()
                  };
                } catch (e) {
                  console.error("Error processing MIFARE Classic tag:", e);
                }
              }
            }
            // 检查是否支持 MIFARE Ultralight
            else if (techList.includes(tag.MIFARE_ULTRALIGHT)) {
              standard = "ISO 14443-3 (Type A)";
              type = "mifare_ultralight";
              const mifareUltralightTag = this.safeGetTagTechnology(tagInfo, tag.MIFARE_ULTRALIGHT, tag.getMifareUltralight);
              // 缓存标签技术对象，供后续操作复用
              this.mifareUltralightTechnology = mifareUltralightTag;
              if (mifareUltralightTag) {
                try {
                  const mifareType = mifareUltralightTag.getType();
                  mifareInfo = this.getMifareUltralightInfo(mifareType);
                } catch (e) {
                  console.error("Error processing MIFARE Ultralight tag:", e);
                }
              }
            }
            else {
              standard = "ISO 14443-3 (Type A)";
              type = "unknown";
            }
          } catch (e) {
            console.error("Error processing NfcA tag:", e);
          }
        }
      }
      // 尝试获取 NfcB 技术类型
      else if (techList.includes(tag.NFC_B)) {
        const nfcBTag = this.safeGetTagTechnology(tagInfo, tag.NFC_B, tag.getNfcB);
        if (nfcBTag) {
          try {
            // 使用官方接口获取协议信息和应用数据
            protocolInfo = this.arrayToHexString(nfcBTag.getRespProtocol());
            applicationData = this.arrayToHexString(nfcBTag.getRespAppData());

            if (techList.includes(tag.ISO_DEP)) {
              type = "iso7816";
              standard = "ISO 14443-4 (Type B)";
              const isoDepTag = this.safeGetTagTechnology(tagInfo, tag.ISO_DEP, tag.getIsoDep);
              if (isoDepTag) {
                try {
                  const hiResponse = isoDepTag.getHiLayerResponse();
                  if (hiResponse) {
                    hiLayerResponse = this.arrayToHexString(hiResponse);
                  }
                } catch (e) {
                  console.error("Error getting hi-layer response:", e);
                }
              }
            } else {
              type = "unknown";
              standard = "ISO 14443-3 (Type B)";
            }
          } catch (e) {
            console.error("Error processing NfcB tag:", e);
          }
        }
      }
      // 尝试获取 NfcF 技术类型 (FeliCa)
      else if (techList.includes(tag.NFC_F)) {
        standard = "ISO 18092 (FeliCa)";
        type = "iso18092";
        const nfcFTag = this.safeGetTagTechnology(tagInfo, tag.NFC_F, tag.getNfcF);
        if (nfcFTag) {
          try {
            // 获取PMm（包含IC代码和制造商参数）
            const pmm = nfcFTag.getPmm();
            if (pmm && pmm.length >= 2) {
              // PMm的前2字节通常是制造商ID
              manufacturer = this.arrayToHexString(pmm.slice(0, 2));
            }
            systemCode = this.arrayToHexString(nfcFTag.getSystemCode());
          } catch (e) {
            console.error("Error processing NfcF tag:", e);
          }
        }
      }
      // 尝试获取 NfcV 技术类型 (ISO 15693)
      else if (techList.includes(tag.NFC_V)) {
        standard = "ISO 15693";
        type = "iso15693";
        const nfcVTag = this.safeGetTagTechnology(tagInfo, tag.NFC_V, tag.getNfcV);
        if (nfcVTag) {
          try {
            dsfId = this.byteToHexString(nfcVTag.getDsfId());
          } catch (e) {
            console.error("Error processing NfcV tag:", e);
          }
        }
      }

      // 检查 NDEF 支持 — 使用 getNdefTag() 统一入口缓存技术对象
      if (techList.includes(tag.NDEF)) {
        const ndefTag = this.getNdefTag(true); // invalidateCache=true，parseTag时重建缓存
        if (ndefTag) {
          try {
            // getNdefTag() 已自动设置 this.ndefTechnology 缓存
            ndefAvailable = true;
            const nfcForumTypeEnum = ndefTag.getNdefTagType();
            ndefType = this.convertNfcForumTypeToString(nfcForumTypeEnum); // 将枚举转换为字符串
            ndefWritable = ndefTag.isNdefWritable();
            ndefCanMakeReadOnly = ndefTag.canSetReadOnly();
            ndefCapacity = ndefTag.getMaxTransmitSize();
          } catch (e) {
            console.error("Error processing NDEF tag:", e);
            // NDEF获取失败时保持默认值，不影响其他功能
          }
        }
      }

    } catch (e) {
      console.error("Error parsing tag:", e);
    }

    // 构建返回的JSON对象
    const result: Record<string, ESObject> = {
      "type": type,
      "id": id,
      "standard": standard,
      "atqa": atqa,
      "sak": sak,
      "historicalBytes": historicalBytes,
      "protocolInfo": protocolInfo,
      "applicationData": applicationData,
      "hiLayerResponse": hiLayerResponse,
      "manufacturer": manufacturer,
      "systemCode": systemCode,
      "dsfId": dsfId,
      "ndefAvailable": ndefAvailable,
      "ndefType": ndefType,
      "ndefWritable": ndefWritable,
      "ndefCanMakeReadOnly": ndefCanMakeReadOnly,
      "ndefCapacity": ndefCapacity
    };

    if (mifareInfo !== null) {
      result["mifareInfo"] = mifareInfo;
    }

    return JSON.stringify(result);
  }

  // 辅助方法：将字节数组转换为十六进制字符串
  private arrayToHexString(array: number[]): string {
    if (!array || array.length === 0) {
      return "";
    }
    return array.map(byte => byte.toString(16).padStart(2, '0')).join('');
  }

  // 辅助方法：将单个字节转换为十六进制字符串
  private byteToHexString(byte: number): string {
    return byte.toString(16).padStart(2, '0');
  }

  // 辅助方法：获取MIFARE Classic类型字符串
  private getMifareClassicTypeString(type: tag.MifareClassicType): string {
    // 根据鸿蒙API文档中的MIFARE Classic类型枚举进行映射
    switch (type) {
      case tag.MifareClassicType.TYPE_UNKNOWN: return "MIFARE_UNKNOWN";
      case tag.MifareClassicType.TYPE_CLASSIC: return "MIFARE_CLASSIC";
      case tag.MifareClassicType.TYPE_PLUS: return "MIFARE_PLUS";
      case tag.MifareClassicType.TYPE_PRO: return "MIFARE_PRO";
      default: return "UNKNOWN";
    }
  }

  private convertNfcForumTypeToString(nfcForumType: tag.NfcForumType): string {
    switch (nfcForumType) {
      case tag.NfcForumType.NFC_FORUM_TYPE_1:
        return "Type 1";
      case tag.NfcForumType.NFC_FORUM_TYPE_2:
        return "Type 2";
      case tag.NfcForumType.NFC_FORUM_TYPE_3:
        return "Type 3";
      case tag.NfcForumType.NFC_FORUM_TYPE_4:
        return "Type 4";
      case tag.NfcForumType.MIFARE_CLASSIC:
        return "MIFARE Classic";
      default:
        console.warn(`Unknown NFC Forum Type: ${nfcForumType}`);
        return "Unknown";
    }
  }


  // 辅助方法：获取MIFARE Ultralight信息
  private getMifareUltralightInfo(type: tag.MifareUltralightType): Record<string, ESObject> {
    // 根据鸿蒙API文档中的MIFARE Ultralight类型枚举返回相应信息
    switch (type) {
      case tag.MifareUltralightType.TYPE_ULTRALIGHT: // ULTRALIGHT
        return {
          "type": "MIFARE_ULTRALIGHT",
          "size": 64,
          "blockSize": 4,
          "blockCount": 16,
          "sectorCount": 0
        };
      case tag.MifareUltralightType.TYPE_ULTRALIGHT_C: // ULTRALIGHT_C
        return {
          "type": "MIFARE_ULTRALIGHT_C",
          "size": 192,
          "blockSize": 4,
          "blockCount": 48,
          "sectorCount": 0
        };
      default:
        return {
          "type": "UNKNOWN",
          "size": 0,
          "blockSize": 4,
          "blockCount": 0,
          "sectorCount": 0
        };
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const ar = new AsyncMethodResult(result);
    this.registerPendingResult(ar);
    try { this.handleMethodCall(call, ar); }
    catch (error) {
      const failure = error as BusinessError;
      if (call.method === "getNFCAvailability" && failure.code === 801) ar.success("not_supported");
      else ar.error("500", failure.message, null);
    }
  }

  handleMethodCall(call: MethodCall, result: AsyncMethodResult) {
    if (this.ability == null) {
      result.error("500", "Cannot call method when not attached to ability", null)
      return
    }

    if (nfcController.isNfcOpen() != true && call.method != "getNFCAvailability") {
      result.error("404", "NFC not available", null)
      return
    }

    // 辅助函数：确保当前标签支持NDEF
    const ensureNDEF = (): boolean => {
      try {
        if (this.ndefTechnology == null) {
          if (this.TagInfo == null) {
            result.error("406", "No tag polled", null);
          } else {
            result.error("405", "NDEF not supported on current tag", null);
          }
          return false;
        }
        return true;
      } catch (e) {
        console.error("Error checking NDEF support:", e);
        result.error("500", "Failed to check NDEF support", null);
        return false;
      }
    };

    switch (call.method){
      case "getNFCAvailability":
        if (nfcController.getNfcState() == null) {
          result.success("not_supported")
        } else if (nfcController.isNfcOpen()) {
          result.success("available")
        } else {
          result.success("disabled")
        }
        break;
      case "poll":
        const timeout: number = call.argument("timeout") as number
        const technologies: number = call.argument("technologies")!! as number
        try {
          this.pollTag(result, timeout, technologies);
        } catch (ex) {
          console.error("Poll error:", ex);
          result.error("500", "Failed to execute Poll task", ex.message || ex.toString());
        }
        break;
      case "finish":
        try {
          this.finishNfcOperations(result);
        } catch (ex) {
          console.error("Close tag error:", ex);
          result.error("500", "Failed to execute Close tag task", ex.message || ex.toString());
        }
        break;
      case "transceive":
        // 参考Android版本的transceive实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#taggetndef9

        // 检查是否有标签连接
        if (this.tagTechnology == null || this.tagTechnology.length === 0) {
          result.error("406", "No tag polled", null);
          return;
        }

        // 获取数据参数
        const data: ESObject = call.argument("data");
        if (!data) {
          result.error("400", "Bad argument", null);
          return;
        }

        // 获取超时参数（可选）
        const transceiveTimeout: number = call.argument("timeout") as number || 5000; // 默认5秒

        try {
          console.log('Starting NFC transceive operation');

          // 执行NFC数据透传操作
          this.performNfcTransceive(data, transceiveTimeout, result);

        } catch (ex) {
          console.error('Error in transceive setup:', ex);
          result.error("500", "Failed to setup NFC transceive operation", ex.message || ex.toString());
        }
        break;
      case "readNDEF":
        // 参考Android版本的readNDEF实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#taggetndef9
        // 使用 getAndConnectNdefTag 统一入口，防止 remoteObject 失效导致 SIGSEGV 崩溃
        const ndefTagForRead = this.getAndConnectNdefTag(result);
        if (!ndefTagForRead) {
          return;
        }

        const cached: boolean = call.argument("cached") as boolean || false;

        try {
          console.log('Starting NDEF read operation, cached:', cached);

          // 执行NDEF读取操作
          this.performNdefRead(ndefTagForRead, cached, result);

        } catch (ex) {
          console.error('Error in readNDEF setup:', ex);
          result.error("500", "Failed to setup NDEF read operation", ex.message || ex.toString());
        }
        break;
      case "writeNDEF":
        // 参考Android版本的writeNDEF实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndeftagwritendef9
        // 使用 getAndConnectNdefTag 统一入口，防止 remoteObject 失效导致 SIGSEGV 崩溃
        const ndefTagForWrite = this.getAndConnectNdefTag(result);
        if (!ndefTagForWrite) {
          return;
        }

        // 检查标签是否可写
        if (!ndefTagForWrite.isNdefWritable()) {
          result.error("405", "Tag not writable", null);
          return;
        }

        const jsonData: string = call.argument("data") as string;
        if (!jsonData) {
          result.error("400", "Missing NDEF data", null);
          return;
        }

        try {
          console.log('Starting NDEF write operation');

          // 执行NDEF写入操作
          this.performNdefWrite(ndefTagForWrite, jsonData, result);

        } catch (ex) {
          console.error('Error in writeNDEF setup:', ex);
          result.error("500", "Failed to setup NDEF write operation", ex.message || ex.toString());
        }
        break;
      case "makeNdefReadOnly":
        // 参考Android版本的makeNdefReadOnly实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndeftagsetreadonly9
        // 使用 getAndConnectNdefTag 统一入口，防止 remoteObject 失效导致 SIGSEGV 崩溃
        const ndefTagForReadOnly = this.getAndConnectNdefTag(result);
        if (!ndefTagForReadOnly) {
          return;
        }

        // 检查标签是否可写
        if (!ndefTagForReadOnly.isNdefWritable()) {
          result.error("405", "Tag not writable", null);
          return;
        }

        try {
          console.log('Starting NDEF make read-only operation');

          // 执行NDEF设置只读操作
          this.performNdefMakeReadOnly(ndefTagForReadOnly, result);

        } catch (ex) {
          console.error('Error in makeNdefReadOnly setup:', ex);
          result.error("500", "Failed to setup NDEF make read-only operation", ex.message || ex.toString());
        }
        break;
      case "authenticateSector":
        // 参考Android版本的authenticateSector实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag

        // 检查是否有MIFARE Classic标签
        if (this.tagTechnology == null || this.tagTechnology.length === 0) {
          result.error("406", "No tag polled", null);
          return;
        }

        // 获取并连接 MIFARE Classic 标签（缓存过期安全）
        const mifareClassicTag = this.getAndConnectMifareClassic(result);
        if (mifareClassicTag == null) {
          return; // 错误已通过 result 返回
        }

        const index: number = call.argument("index") as number;
        if (index === undefined || index === null) {
          result.error("400", "Missing sector index", null);
          return;
        }

        const maxSector = mifareClassicTag.getSectorCount();
        if (index < 0 || index >= maxSector) {
          result.error("400", `Invalid sector index ${index}, should be in (0, ${maxSector})`, null);
          return;
        }

        const keyA: ESObject = call.argument("keyA");
        const keyB: ESObject = call.argument("keyB");

        if (!keyA && !keyB) {
          result.error("400", "No keys provided", null);
          return;
        }

        try {
          console.log('Starting MIFARE Classic sector authentication');

          // 执行MIFARE Classic扫区认证操作
          this.performMifareAuthentication(mifareClassicTag, index, keyA, keyB, result);

        } catch (ex) {
          console.error('Error in authenticateSector setup:', ex);
          result.error("500", "Failed to setup MIFARE authentication", ex.message || ex.toString());
        }
        break;
      case "readBlock":
        // 参考Android版本的readBlock实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag

        // 检查是否有MIFARE标签
        if (this.tagTechnology == null || this.tagTechnology.length === 0) {
          result.error("406", "No tag polled", null);
          return;
        }

        // 获取块索引参数
        const blockIndex: number = call.argument("index") as number;
        if (blockIndex === undefined || blockIndex === null) {
          result.error("400", "Missing block index", null);
          return;
        }

        try {
          console.log(`Starting MIFARE block ${blockIndex} read operation`);

          // 执行MIFARE块读取操作
          this.performMifareBlockRead(blockIndex, result);

        } catch (ex) {
          console.error('Error in readBlock setup:', ex);
          result.error("500", "Failed to setup MIFARE block read operation", ex.message || ex.toString());
        }
        break;
      case "readSector":
        // 参考Android版本的readSector实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag

        // 检查是否有MIFARE Classic标签（readSector仅适用于MIFARE Classic）
        if (this.tagTechnology == null || this.tagTechnology.length === 0) {
          result.error("406", "No tag polled", null);
          return;
        }

        // 检查是否支持MIFARE Classic技术
        if (!this.tagTechnology.includes(tag.MIFARE_CLASSIC)) {
          result.error("406", "No Mifare Classic tag polled", null);
          return;
        }

        // 获取扇区索引参数
        const sectorIndex: number = call.argument("index") as number;
        if (sectorIndex === undefined || sectorIndex === null) {
          result.error("400", "Missing sector index", null);
          return;
        }

        try {
          console.log(`Starting MIFARE Classic sector ${sectorIndex} read operation`);

          // 执行MIFARE Classic扇区读取操作
          this.performMifareSectorRead(sectorIndex, result);

        } catch (ex) {
          console.error('Error in readSector setup:', ex);
          result.error("500", "Failed to setup MIFARE sector read operation", ex.message || ex.toString());
        }
        break;
      case "writeBlock":
        // 参考Android版本的writeBlock实现，使用鸿蒙NFC API
        // 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag

        // 检查是否有MIFARE标签
        if (this.tagTechnology == null || this.tagTechnology.length === 0) {
          result.error("406", "No tag polled", null);
          return;
        }

        // 获取块索引和数据参数
        const writeBlockIndex: number = call.argument("index") as number;
        if (writeBlockIndex === undefined || writeBlockIndex === null) {
          result.error("400", "Missing block index", null);
          return;
        }

        const writeData: ESObject = call.argument("data");
        if (!writeData) {
          result.error("400", "Missing data", null);
          return;
        }

        try {
          console.log(`Starting MIFARE block ${writeBlockIndex} write operation`);

          // 执行MIFARE块写入操作
          this.performMifareBlockWrite(writeBlockIndex, writeData, result);

        } catch (ex) {
          console.error('Error in writeBlock setup:', ex);
          result.error("500", "Failed to setup MIFARE block write operation", ex.message || ex.toString());
        }
        break;
      case "setIosAlertMessage":
        // do nothing, just for compatibility
        result.success("")
        break;
    }
  }

  /**
   * 执行NDEF写入操作
   * 参考Android版本的NDEF写入实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndeftagwritendef9
   */
  private performNdefWrite(ndefTag: tag.NdefTag, jsonData: string, result: MethodResult): void {
    try {
      console.log('Performing NDEF write operation');

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(ndefTag, result)) {
        return;
      }

      // 解析JSON数据为NDEF记录数组
      const recordsData = this.parseJsonToNdefRecords(jsonData);
      if (recordsData.length === 0) {
        result.error("400", "No valid NDEF records provided", null);
        return;
      }

      // 构建NDEF消息
      const ndefMessage = this.createNdefMessage(recordsData);

      // 根据鸿蒙官方API文档，使用writeNdef方法写入NDEF消息
      if (typeof ndefTag.writeNdef === 'function') {
        // 使用Promise处理异步操作
        ndefTag.writeNdef(ndefMessage)
          .then(() => {
            console.log('NDEF message written successfully');
            result.success("");
          })
          .catch((error: ESObject) => {
            console.error('NDEF write failed:', error);
            const errorMessage = this.extractErrorMessage(error);

            // 根据错误类型返回相应的错误代码
            if (errorMessage.includes('Communication') || errorMessage.includes('IOException')) {
              result.error("500", "Communication error during NDEF write", errorMessage);
            } else if (errorMessage.includes('tag') && errorMessage.includes('removed')) {
              result.error("503", "Tag was removed during NDEF write", errorMessage);
            } else if (errorMessage.includes('not supported')) {
              result.error("405", "NDEF write not supported on this tag", errorMessage);
            } else if (errorMessage.includes('read-only') || errorMessage.includes('readonly')) {
              result.error("405", "Tag is read-only", errorMessage);
            } else if (errorMessage.includes('capacity') || errorMessage.includes('size')) {
              result.error("413", "NDEF message too large", errorMessage);
            } else {
              result.error("500", "NDEF write operation failed", errorMessage);
            }
          });

      } else {
        // 如果鸿蒙官方API未实现，返回错误
        console.error('NDEF writeNdef method not available in HarmonyOS API');
        result.error("405", "NDEF write not supported on this platform", null);
      }

    } catch (ex) {
      console.error('Error in performNdefWrite:', ex);
      result.error("500", "Failed to perform NDEF write", ex.message || ex.toString());
    }
  }

  /**
   * 执行NDEF设置只读操作
   * 参考Android版本的makeNdefReadOnly实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndeftagsetreadonly9
   *
   * **警告：此操作不可逆转！一旦设置为只读，NDEF标签将无法再次写入。**
   */
  private performNdefMakeReadOnly(ndefTag: tag.NdefTag, result: MethodResult): void {
    try {
      console.log('Performing NDEF make read-only operation - WARNING: This cannot be undone!');

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(ndefTag, result)) {
        return;
      }

      // 根据鸿蒙官方API文档，使用setReadOnly方法设置NDEF标签为只读
      if (typeof ndefTag.setReadOnly === 'function') {
        // 使用Promise处理异步操作
        ndefTag.setReadOnly()
          .then(() => {
            console.log('NDEF tag successfully set to read-only');
            result.success("");
          })
          .catch((error: ESObject) => {
            console.error('NDEF make read-only failed:', error);
            const errorMessage = this.extractErrorMessage(error);

            // 根据错误类型返回相应的错误代码
            if (errorMessage.includes('Communication') || errorMessage.includes('IOException')) {
              result.error("500", "Communication error during NDEF make read-only", errorMessage);
            } else if (errorMessage.includes('tag') && errorMessage.includes('removed')) {
              result.error("503", "Tag was removed during NDEF make read-only", errorMessage);
            } else if (errorMessage.includes('not supported')) {
              result.error("405", "NDEF make read-only not supported on this tag", errorMessage);
            } else if (errorMessage.includes('read-only') || errorMessage.includes('readonly')) {
              result.error("405", "Tag is already read-only", errorMessage);
            } else if (errorMessage.includes('not writable')) {
              result.error("405", "Tag is not writable", errorMessage);
            } else {
              result.error("500", "Failed to lock NDEF tag", errorMessage);
            }
          });

      } else {
        // 如果鸿蒙官方API未实现，返回错误
        console.error('NDEF setReadOnly method not available in HarmonyOS API');
        result.error("405", "NDEF make read-only not supported on this platform", null);
      }

    } catch (ex) {
      console.error('Error in performNdefMakeReadOnly:', ex);
      result.error("500", "Failed to perform NDEF make read-only", ex.message || ex.toString());
    }
  }

  /**
   * 获取MIFARE Classic标签对象（统一入口）
   * 优先使用缓存的标签技术对象，避免remoteObject失效；
   * 若缓存为空则从TagInfo创建并缓存。
   * @param invalidateCache 是否强制清除缓存并重建对象（标签连接失效时使用）
   * @return MifareClassicTag 或 null（标签不是MIFARE Classic时）
   */
  private getMifareClassicTag(invalidateCache: boolean = false): tag.MifareClassicTag | null {
    try {
      if (invalidateCache) {
        console.log('Invalidating MIFARE Classic cache, rebuilding from TagInfo');
        this.mifareClassicTechnology = null;
        // 失效重建时同时清空认证缓存，因为新对象需要重新认证
        this.mifareAuthCache.clear();
      }
      if (this.mifareClassicTechnology != null) {
        console.log('Using cached MifareClassic tag object');
        return this.mifareClassicTechnology;
      }
      if (this.TagInfo && this.TagInfo.technology.includes(tag.MIFARE_CLASSIC)) {
        const mifareTag = tag.getMifareClassic(this.TagInfo);
        this.mifareClassicTechnology = mifareTag;
        return mifareTag;
      }
    } catch (e) {
      console.error('Error getting MIFARE Classic tag:', e);
      // 创建失败时清除缓存，防止持有无效引用
      this.mifareClassicTechnology = null;
    }
    return null;
  }

  /**
   * 计算MIFARE Classic标签的总块数
   * @param mifareTag MIFARE Classic标签对象
   * @return 总块数（所有扇区块数之和）
   */
  private getTotalBlockCount(mifareTag: tag.MifareClassicTag): number {
    try {
      const sectorCount = mifareTag.getSectorCount();
      let totalBlockCount = 0;
      for (let i = 0; i < sectorCount; i++) {
        totalBlockCount += Math.floor(mifareTag.getBlockCountInSector(i));
      }
      return totalBlockCount;
    } catch (e) {
      console.error('Error calculating total block count:', e);
      // 返回0表示无法计算，调用方应检查返回值有效性
      return 0;
    }
  }

  /**
   * 获取MIFARE Ultralight标签对象（统一入口）
   * 优先使用缓存的标签技术对象，避免remoteObject失效；
   * 若缓存为空则从TagInfo创建并缓存。
   * @param invalidateCache 是否强制清除缓存并重建对象（标签连接失效时使用）
   * @return MifareUltralightTag 或 null（标签不是MIFARE Ultralight时）
   */
  private getMifareUltralightTag(invalidateCache: boolean = false): tag.MifareUltralightTag | null {
    try {
      if (invalidateCache) {
        console.log('Invalidating MIFARE Ultralight cache, rebuilding from TagInfo');
        this.mifareUltralightTechnology = null;
      }
      if (this.mifareUltralightTechnology != null) {
        console.log('Using cached MifareUltralight tag object');
        return this.mifareUltralightTechnology;
      }
      if (this.TagInfo && this.TagInfo.technology.includes(tag.MIFARE_ULTRALIGHT)) {
        const mifareTag = tag.getMifareUltralight(this.TagInfo);
        this.mifareUltralightTechnology = mifareTag;
        return mifareTag;
      }
    } catch (e) {
      console.error('Error getting MIFARE Ultralight tag:', e);
      // 创建失败时清除缓存，防止持有无效引用
      this.mifareUltralightTechnology = null;
    }
    return null;
  }

  /**
   * 获取NDEF标签对象（统一入口）
   * 优先使用缓存的标签技术对象，避免remoteObject失效；
   * 若缓存为空则从TagInfo创建并缓存。
   * @param invalidateCache 是否强制清除缓存并重建对象（标签连接失效时使用）
   * @return NdefTag 或 null（标签不支持NDEF时）
   */
  private getNdefTag(invalidateCache: boolean = false): tag.NdefTag | null {
    try {
      if (invalidateCache) {
        console.log('Invalidating NDEF cache, rebuilding from TagInfo');
        this.ndefTechnology = null;
      }
      if (this.ndefTechnology != null) {
        console.log('Using cached NDEF tag object');
        return this.ndefTechnology;
      }
      if (this.TagInfo && this.TagInfo.technology.includes(tag.NDEF)) {
        const ndefTag = tag.getNdef(this.TagInfo);
        this.ndefTechnology = ndefTag;
        return ndefTag;
      }
    } catch (e) {
      console.error('Error getting NDEF tag:', e);
      // 创建失败时清除缓存，防止持有无效引用
      this.ndefTechnology = null;
    }
    return null;
  }

  /**
   * 清除所有缓存的标签技术对象引用
   * 在标签更换检测时调用，释放旧标签的缓存引用
   * 注意：HarmonyOS NFC TagSession API 没有 disconnect() 方法，
   * 只有 connect() 和 isConnected()。标签移开后连接自然失效，
   * 这里只需将缓存引用设为 null，防止旧引用干扰新标签操作。
   */
  private disconnectCachedTagTechnologies(): void {
    // TagSession 没有 disconnect() 方法，标签移开后 remoteObject 自动失效
    // 只需清除缓存引用，rebuildStaleTagTechnology 会从 TagInfo 重建
    this.mifareClassicTechnology = null;
    this.mifareUltralightTechnology = null;
    this.ndefTechnology = null;
    console.log('Cleared all cached tag technology references on tag change');
  }

  /**
   * 确保标签已建立连接
   * 鸿蒙API要求在读写标签之前必须先调用connect()建立连接
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-tagsession#connect9
   * @return true 表示已连接（或连接成功），false 表示连接失败
   */
  private ensureTagConnected(tagTech: ESObject, result: MethodResult): boolean {
    try {
      // 第一次尝试：检查连接状态并连接
      if (typeof tagTech.isConnected === 'function') {
        if (tagTech.isConnected()) {
          console.log('Tag already connected');
          // 连接显示正常，但 remoteObject 可能已失效（标签移开后本地 Session 状态滞后）
          // 做一次轻量级验证：调用 isConnected() 的过程中如果 remoteObject 无效会抛异常
          // 如果未抛异常，认为连接有效
          return true;
        }
      }
      console.log('Tag not connected, calling connect()');
      if (typeof tagTech.connect === 'function') {
        tagTech.connect();
        console.log('Tag connected successfully');
        return true;
      } else {
        console.error('connect() method not available on tag technology');
        result.error("503", "Tag connect() method not available - cannot establish connection", null);
        return false;
      }
    } catch (e) {
      // connect() 或 isConnected() 抛出异常 → remoteObject 已失效（标签移开）
      // 尝试：清除缓存 → 重建技术对象
      // 重建后由调用者（getAndConnectMifareClassic/Ultralight）从缓存重新获取并连接
      console.error('Error connecting to tag (cached object may be stale):', e);

      const rebuilt = this.rebuildStaleTagTechnology(tagTech);
      if (rebuilt) {
        // 缓存重建成功，返回 true 表示需要调用者重新从缓存获取并连接
        // 注意：此时缓存中的新对象尚未连接，调用者需再次调用 ensureTagConnected
        console.log('Tag technology cache rebuilt successfully, caller should re-connect');
        return true;
      }

      // 无法重建（标签类型不匹配或 TagInfo 已清理）→ 标签已不在场
      result.error("503", "Failed to connect to tag - tag may have been removed, please poll again", e?.message || e?.toString() || 'Unknown error');
      return false;
    }
  }

  /**
   * 重建失效的标签技术对象缓存（缓存过期修复的核心方法）
   *
   * 当缓存的 MIFARE Classic/Ultralight 对象因标签移开导致 remoteObject 失效时，
   * 清除缓存并从 TagInfo 重新创建技术对象。
   *
   * 适用场景：ensureTagConnected 中 connect()/isConnected() 抛出异常，
   * 说明缓存的标签技术对象的底层 IPC 句柄已失效。
   *
   * @param staleTag 失效的标签技术对象（用于判断类型）
   * @return true 表示缓存重建成功，false 表示无法重建
   */
  private rebuildStaleTagTechnology(staleTag: ESObject): boolean {
    console.log('Attempting to rebuild stale tag technology object...');

    // 检查 TagInfo 是否仍然有效（如果 finish() 已清理 TagInfo 则无法重建）
    if (this.TagInfo === null || this.TagInfo === undefined) {
      console.error('TagInfo is null, cannot rebuild tag technology - session may have been finished');
      return false;
    }

    try {
      // 通过 technology 列表判断标签类型，重建对应的技术对象
      if (this.TagInfo.technology.includes(tag.MIFARE_CLASSIC)) {
        console.log('Rebuilding MIFARE Classic technology object');
        const rebuiltTag = this.getMifareClassicTag(true); // invalidateCache=true 强制重建
        if (rebuiltTag !== null) {
          console.log('MIFARE Classic technology object rebuilt successfully');
          return true;
        }
      }

      if (this.TagInfo.technology.includes(tag.MIFARE_ULTRALIGHT)) {
        console.log('Rebuilding MIFARE Ultralight technology object');
        const rebuiltTag = this.getMifareUltralightTag(true); // invalidateCache=true 强制重建
        if (rebuiltTag !== null) {
          console.log('MIFARE Ultralight technology object rebuilt successfully');
          return true;
        }
      }

      if (this.TagInfo.technology.includes(tag.NDEF)) {
        console.log('Rebuilding NDEF technology object');
        const rebuiltTag = this.getNdefTag(true); // invalidateCache=true 强制重建
        if (rebuiltTag !== null) {
          console.log('NDEF technology object rebuilt successfully');
          return true;
        }
      }

      // 对于其他标签类型（NfcA/B/F/V、IsoDep），没有缓存机制
      // 这些类型在每次操作方法中直接从 TagInfo 获取
      // 如果 staleTag 是这些类型，说明标签确实已不在场
      console.log('No cache rebuild mechanism for this tag type, tag may be gone');
      return false;

    } catch (e) {
      console.error('Error rebuilding tag technology:', e);
      return false;
    }
  }

  /**
   * 获取并连接 MIFARE Classic 标签对象（缓存过期安全版本）
   *
   * 统一处理"获取缓存对象 → ensureTagConnected → 缓存重建后重新获取"的完整流程，
   * 解决 ensureTagConnected 中 rebuildStaleTagTechnology 更新了缓存但局部变量仍指向旧对象的问题。
   *
   * @param result MethodResult 用于返回错误
   * @return 已连接的 MifareClassicTag，或 null（获取/连接失败时已通过 result 返回错误）
   */
  private getAndConnectMifareClassic(result: MethodResult): tag.MifareClassicTag | null {
    let mifareClassicTag = this.getMifareClassicTag();
    if (!mifareClassicTag) {
      result.error("406", "No Mifare Classic tag polled", null);
      return null;
    }
    if (!this.ensureTagConnected(mifareClassicTag, result)) {
      return null;
    }
    // ensureTagConnected 可能因缓存过期重建了 this.mifareClassicTechnology
    // 并返回 true（表示缓存已重建但新对象尚未连接），
    // 需重新从缓存获取并再次调用 ensureTagConnected 来真正连接
    mifareClassicTag = this.getMifareClassicTag();
    if (!mifareClassicTag) {
      result.error("406", "Failed to get MIFARE Classic tag after connection recovery", null);
      return null;
    }
    if (!this.ensureTagConnected(mifareClassicTag, result)) {
      return null;
    }
    return mifareClassicTag;
  }

  /**
   * 获取并连接 MIFARE Ultralight 标签对象（缓存过期安全版本）
   *
   * 统一处理"获取缓存对象 → ensureTagConnected → 缓存重建后重新获取"的完整流程，
   * 解决 ensureTagConnected 中 rebuildStaleTagTechnology 更新了缓存但局部变量仍指向旧对象的问题。
   *
   * @param result MethodResult 用于返回错误
   * @return 已连接的 MifareUltralightTag，或 null（获取/连接失败时已通过 result 返回错误）
   */
  private getAndConnectMifareUltralight(result: MethodResult): tag.MifareUltralightTag | null {
    let mifareUltralightTag = this.getMifareUltralightTag();
    if (!mifareUltralightTag) {
      result.error("406", "No Mifare Ultralight tag polled", null);
      return null;
    }
    if (!this.ensureTagConnected(mifareUltralightTag, result)) {
      return null;
    }
    // ensureTagConnected 可能因缓存过期重建了 this.mifareUltralightTechnology
    // 并返回 true（表示缓存已重建但新对象尚未连接），
    // 需重新从缓存获取并再次调用 ensureTagConnected 来真正连接
    mifareUltralightTag = this.getMifareUltralightTag();
    if (!mifareUltralightTag) {
      result.error("406", "Failed to get MIFARE Ultralight tag after connection recovery", null);
      return null;
    }
    if (!this.ensureTagConnected(mifareUltralightTag, result)) {
      return null;
    }
    return mifareUltralightTag;
  }

  /**
   * 获取并连接 NDEF 标签对象（缓存过期安全版本）
   *
   * 统一处理"获取缓存对象 → ensureTagConnected → 缓存重建后重新获取"的完整流程，
   * 解决 ensureTagConnected 中 rebuildStaleTagTechnology 更新了缓存但局部变量仍指向旧对象的问题。
   * 防止 NDEF write/read 操作时因 remoteObject 失效导致 SIGSEGV 崩溃。
   *
   * @param result MethodResult 用于返回错误
   * @return 已连接的 NdefTag，或 null（获取/连接失败时已通过 result 返回错误）
   */
  private getAndConnectNdefTag(result: MethodResult): tag.NdefTag | null {
    let ndefTag = this.getNdefTag();
    if (!ndefTag) {
      if (this.TagInfo == null) {
        result.error("406", "No tag polled", null);
      } else {
        result.error("405", "NDEF not supported on current tag", null);
      }
      return null;
    }
    if (!this.ensureTagConnected(ndefTag, result)) {
      return null;
    }
    // ensureTagConnected 可能因缓存过期重建了 this.ndefTechnology
    // 并返回 true（表示缓存已重建但新对象尚未连接），
    // 需重新从缓存获取并再次调用 ensureTagConnected 来真正连接
    ndefTag = this.getNdefTag();
    if (!ndefTag) {
      result.error("405", "Failed to get NDEF tag after connection recovery", null);
      return null;
    }
    if (!this.ensureTagConnected(ndefTag, result)) {
      return null;
    }
    return ndefTag;
  }

  /**
   * 执行MIFARE Classic扫区认证操作
   * 参考Android版本的authenticateSector实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag
   */
  private performMifareAuthentication(mifareTag: tag.MifareClassicTag, sectorIndex: number, keyA: ESObject | null, keyB: ESObject | null, result: MethodResult): void {
    try {
      console.log(`Performing MIFARE Classic sector ${sectorIndex} authentication`);

      // 标签连接已在调用方（getAndConnectMifareClassic）中确保，此处无需重复连接

      // keyA 优先，如果同时提供了keyA和keyB，优先使用keyA
      if (keyA !== null && keyA !== undefined) {
        // 处理keyA认证
        const keyABytes = this.canonicalizeKeyData(keyA);
        if (keyABytes === null || keyABytes.length !== 6) {
          result.error("400", "Invalid keyA format - must be 6 bytes", null);
          return;
        }

        // 根据鸿蒙官方API文档，使用authenticateSector方法，isKeyA设置为true
        mifareTag.authenticateSector(sectorIndex, keyABytes, true)
          .then(() => {
            console.log(`MIFARE Classic sector ${sectorIndex} authentication with keyA successful`);
            // 缓存认证信息，供后续读写操作重新认证使用
            // 优先更新已有缓存条目，保留同一扇区已认证的Key B
            let authInfo = this.mifareAuthCache.get(sectorIndex);
            if (authInfo === undefined || authInfo === null) {
              authInfo = new MifareAuthInfo();
            }
            authInfo.keyA = keyABytes;
            authInfo.lastUsedKey = 'A';
            this.mifareAuthCache.set(sectorIndex, authInfo);
            result.success(true);
          })
          .catch((error: ESObject) => {
            console.error('MIFARE authentication with keyA failed:', error);
            const errorMessage = this.extractErrorMessage(error);

            // 根据鸿蒙API文档的错误码返回相应的错误代码
            if (errorMessage.includes('3100201')) {
              result.error("503", "Tag running state is abnormal", errorMessage);
            } else if (errorMessage.includes('3100204')) {
              result.error("500", "Tag I/O operation failed", errorMessage);
            } else if (errorMessage.includes('401')) {
              result.error("400", "Parameter check failed", errorMessage);
            } else if (errorMessage.includes('201')) {
              result.error("403", "Permission denied", errorMessage);
            } else if (errorMessage.includes('Communication') || errorMessage.includes('IOException')) {
              result.error("500", "Communication error during MIFARE authentication", errorMessage);
            } else if (errorMessage.includes('tag') && errorMessage.includes('removed')) {
              result.error("503", "Tag was removed during MIFARE authentication", errorMessage);
            } else if (errorMessage.includes('not supported')) {
              result.error("405", "MIFARE authentication not supported on this tag", errorMessage);
            } else if (errorMessage.includes('authentication') && errorMessage.includes('failed')) {
              result.error("401", "MIFARE authentication failed - invalid key", errorMessage);
            } else {
              // 默认认为认证失败（密钥错误）
              result.success(false);
            }
          });

      } else if (keyB !== null && keyB !== undefined) {
        // 处理keyB认证
        const keyBBytes = this.canonicalizeKeyData(keyB);
        if (keyBBytes === null || keyBBytes.length !== 6) {
          result.error("400", "Invalid keyB format - must be 6 bytes", null);
          return;
        }

        // 根据鸿蒙官方API文档，使用authenticateSector方法，isKeyA设置为false
        mifareTag.authenticateSector(sectorIndex, keyBBytes, false)
          .then(() => {
            console.log(`MIFARE Classic sector ${sectorIndex} authentication with keyB successful`);
            // 缓存认证信息，供后续读写操作重新认证使用
            // 优先更新已有缓存条目，保留同一扇区已认证的Key A
            let authInfo = this.mifareAuthCache.get(sectorIndex);
            if (authInfo === undefined || authInfo === null) {
              authInfo = new MifareAuthInfo();
            }
            authInfo.keyB = keyBBytes;
            authInfo.lastUsedKey = 'B';
            this.mifareAuthCache.set(sectorIndex, authInfo);
            result.success(true);
          })
          .catch((error: ESObject) => {
            console.error('MIFARE authentication with keyB failed:', error);
            const errorMessage = this.extractErrorMessage(error);

            // 根据鸿蒙API文档的错误码返回相应的错误代码
            if (errorMessage.includes('3100201')) {
              result.error("503", "Tag running state is abnormal", errorMessage);
            } else if (errorMessage.includes('3100204')) {
              result.error("500", "Tag I/O operation failed", errorMessage);
            } else if (errorMessage.includes('401')) {
              result.error("400", "Parameter check failed", errorMessage);
            } else if (errorMessage.includes('201')) {
              result.error("403", "Permission denied", errorMessage);
            } else if (errorMessage.includes('Communication') || errorMessage.includes('IOException')) {
              result.error("500", "Communication error during MIFARE authentication", errorMessage);
            } else if (errorMessage.includes('tag') && errorMessage.includes('removed')) {
              result.error("503", "Tag was removed during MIFARE authentication", errorMessage);
            } else if (errorMessage.includes('not supported')) {
              result.error("405", "MIFARE authentication not supported on this tag", errorMessage);
            } else if (errorMessage.includes('authentication') && errorMessage.includes('failed')) {
              result.error("401", "MIFARE authentication failed - invalid key", errorMessage);
            } else {
              // 默认认为认证失败（密钥错误）
              result.success(false);
            }
          });

      } else {
        result.error("400", "No valid keys provided", null);
      }

    } catch (ex) {
      console.error('Error in performMifareAuthentication:', ex);
      result.error("500", "Failed to perform MIFARE authentication", ex.message || ex.toString());
    }
  }

  /**
   * 重新认证MIFARE Classic扇区
   * 鸿蒙的MIFARE Classic认证状态不跨Method Channel调用保持，
   * 每次readBlock/writeBlock/readSector前需要重新认证。
   * 使用缓存的认证信息（扇区号、密钥类型、密钥值）进行重新认证。
   * @return Promise<void> 认证成功时resolve，失败时reject
   */
  private async reauthenticateMifareClassic(mifareTag: tag.MifareClassicTag, blockIndex: number): Promise<void> {
    // 根据块号动态计算所属扇区号（兼容1K/4K标签）
    const sectorIndex = this.blockToSector(mifareTag, blockIndex);

    if (sectorIndex < 0) {
      throw new Error(`Invalid block index ${blockIndex} - cannot map to sector`);
    }

    // 从多扇区缓存中查找认证信息
    const cachedAuth = this.mifareAuthCache.get(sectorIndex);
    if (cachedAuth && (cachedAuth.keyA !== null || cachedAuth.keyB !== null)) {
      console.log(`Re-authenticating sector ${sectorIndex} for block ${blockIndex} (cached auth)`);
      // 按用户最后成功认证使用的密钥类型选择密钥，避免keyA优先导致keyB-only扇区认证失败
      if (cachedAuth.lastUsedKey === 'B' && cachedAuth.keyB !== null) {
        await mifareTag.authenticateSector(sectorIndex, cachedAuth.keyB, false);
      } else if (cachedAuth.keyA !== null) {
        await mifareTag.authenticateSector(sectorIndex, cachedAuth.keyA, true);
      } else {
        await mifareTag.authenticateSector(sectorIndex, cachedAuth.keyB!, false);
      }
      console.log(`Re-authentication of sector ${sectorIndex} successful`);
      return;
    }

    // 无缓存认证信息，尝试使用默认密钥 FFFFFFFFFFFF
    // 适用于出厂默认配置的 MIFARE Classic 标签
    console.warn(`No cached auth for sector ${sectorIndex}, trying default key FFFFFFFFFFFF`);
    const defaultKey: number[] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];
    try {
      await mifareTag.authenticateSector(sectorIndex, defaultKey, true);
    } catch (e) {
      throw new Error(`Authentication failed for sector ${sectorIndex} (default key rejected). Please call authenticateSector with the correct key first.`);
    }
    const authInfo = new MifareAuthInfo();
    authInfo.keyA = defaultKey;
    this.mifareAuthCache.set(sectorIndex, authInfo);
    console.log(`Re-authentication of sector ${sectorIndex} successful (default key)`);
  }

  /**
   * 根据块索引计算所属扇区号（兼容MIFARE Classic 1K/4K标签）
   * 1K标签: 所有扇区各4个块
   * 4K标签: 扇区0-31各4个块，扇区32-39各16个块
   * 使用鸿蒙API的getBlockCountInSector方法动态计算，确保与标签实际结构一致
   * @param mifareTag MIFARE Classic标签对象
   * @param blockIndex 块索引
   * @return 扇区号，如果超出范围返回-1
   */
  private blockToSector(mifareTag: tag.MifareClassicTag, blockIndex: number): number {
    try {
      const sectorCount = mifareTag.getSectorCount();
      let accumulatedBlocks = 0;
      for (let s = 0; s < sectorCount; s++) {
        const blocksInSector = mifareTag.getBlockCountInSector(s);
        if (blockIndex < accumulatedBlocks + blocksInSector) {
          return s;
        }
        accumulatedBlocks += blocksInSector;
      }
      return -1;
    } catch (e) {
      console.error('Error calculating block to sector:', e);
      return -1;
    }
  }

  /**
   * 执行MIFARE块读取操作
   * 参考Android版本的readBlock实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareultralight
   *
   * MIFARE Classic: 使用readSingleBlock读取16字节块
   * MIFARE Ultralight: 使用readMultiplePages读取4个页面（总计16字节）
   */
  private performMifareBlockRead(blockIndex: number, result: MethodResult): void {
    try {
      console.log(`Performing MIFARE block ${blockIndex} read operation`);

      // 检查MIFARE Classic标签
      if (this.TagInfo && this.TagInfo.technology.includes(tag.MIFARE_CLASSIC)) {
        const mifareClassicTag = this.getAndConnectMifareClassic(result);
        if (mifareClassicTag) {
          // 验证块索引的有效性
          const totalBlockCount = this.getTotalBlockCount(mifareClassicTag);

          if (blockIndex < 0 || blockIndex >= totalBlockCount) {
            result.error("400", `Invalid block index ${blockIndex}, should be in (0, ${totalBlockCount})`, null);
            return;
          }

          // 使用鸿蒙官方API读取块数据
          if (typeof mifareClassicTag.readSingleBlock === 'function') {
            // 鸿蒙的MIFARE Classic认证状态不跨Method Channel调用保持
            // 需要在每次读取前重新认证
            this.reauthenticateMifareClassic(mifareClassicTag, blockIndex)
              .then(() => {
                mifareClassicTag.readSingleBlock(blockIndex)
                  .then((data: number[]) => {
                    console.log(`MIFARE Classic block ${blockIndex} read successful`);
                    // 转换为Uint8Array格式返回
                    const uint8Data = new Uint8Array(data);
                    result.success(uint8Data);
                  })
                  .catch((error: ESObject) => {
                    console.error('MIFARE Classic block read failed:', error);
                    const errorMessage = this.extractErrorMessage(error);
                    this.handleMifareError(error, "block read", result);
                  });
              })
              .catch((authError: ESObject) => {
                console.error('MIFARE Classic re-authentication failed before read:', authError);
                result.error("401", "MIFARE re-authentication failed - please authenticate first", authError?.message || authError?.toString() || 'Unknown error');
              });
          } else {
            // 如果鸿蒙官方API未实现，返回错误
            console.error('MIFARE Classic readSingleBlock method not available in HarmonyOS API');
            result.error("405", "MIFARE Classic block read not supported on this platform", null);
          }
          return;
        }
      }

      // 检查MIFARE Ultralight标签
      if (this.TagInfo && this.TagInfo.technology.includes(tag.MIFARE_ULTRALIGHT)) {
        const mifareUltralightTag = this.getAndConnectMifareUltralight(result);
        if (mifareUltralightTag) {
          // MIFARE Ultralight使用页索引，验证页索引的有效性
          const ultralightType = mifareUltralightTag.getType();
          const mifareInfo = this.getMifareUltralightInfo(ultralightType);
          const maxPages = mifareInfo["blockCount"] as number;

          if (blockIndex < 0 || blockIndex >= maxPages) {
            result.error("400", `Invalid page index ${blockIndex}, should be in (0, ${maxPages})`, null);
            return;
          }

          // 使用鸿蒙官方API读取多个页面（MIFARE Ultralight通常一次读取4个页面）
          if (typeof mifareUltralightTag.readMultiplePages === 'function') {
            mifareUltralightTag.readMultiplePages(blockIndex)
              .then((data: number[]) => {
                console.log(`MIFARE Ultralight pages starting from ${blockIndex} read successful`);
                // 转换为Uint8Array格式返回
                const uint8Data = new Uint8Array(data);
                result.success(uint8Data);
              })
              .catch((error: ESObject) => {
                console.error('MIFARE Ultralight pages read failed:', error);
                this.handleMifareError(error, "pages read", result);
              });
          } else {
            // 如果鸿蒙官方API未实现，返回错误
            console.error('MIFARE Ultralight readMultiplePages method not available in HarmonyOS API');
            result.error("405", "MIFARE Ultralight pages read not supported on this platform", null);
          }
          return;
        }
      }

      // 如果不是MIFARE标签，返回错误
      result.error("405", "Cannot invoke read on non-Mifare card", null);

    } catch (ex) {
      console.error('Error in performMifareBlockRead:', ex);
      result.error("500", "Failed to perform MIFARE block read", ex.message || ex.toString());
    }
  }

  /**
   * 执行MIFARE块写入操作
   * 参考Android版本的writeBlock实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag
   * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareultralight
   *
   * MIFARE Classic: 使用writeSingleBlock写入16字节块
   * MIFARE Ultralight: 使用writeSinglePage写入4字节页面
   */
  private performMifareBlockWrite(blockIndex: number, writeData: ESObject, result: MethodResult): void {
    try {
      console.log(`Performing MIFARE block ${blockIndex} write operation`);

      // 解析和标准化数据
      const dataBytes = this.canonicalizeKeyData(writeData);
      if (!dataBytes) {
        result.error("400", "Invalid data format", null);
        return;
      }

      // 检查MIFARE Classic标签
      if (this.TagInfo && this.TagInfo.technology.includes(tag.MIFARE_CLASSIC)) {
        const mifareClassicTag = this.getAndConnectMifareClassic(result);
        if (mifareClassicTag) {
          // 验证块索引的有效性
          const totalBlockCount = this.getTotalBlockCount(mifareClassicTag);

          if (blockIndex < 0 || blockIndex >= totalBlockCount) {
            result.error("400", `Invalid block index ${blockIndex}, should be in (0, ${totalBlockCount})`, null);
            return;
          }

          // 验证数据大小（MIFARE Classic块大小为16字节）
          if (dataBytes.length !== 16) {
            result.error("400", `Invalid data size ${dataBytes.length}, should be 16 bytes for MIFARE Classic`, null);
            return;
          }

          // 使用鸿蒙官方API写入块数据
          if (typeof mifareClassicTag.writeSingleBlock === 'function') {
            // 转换Uint8Array为数组
            const dataArray = Array.from(dataBytes);
            // 鸿蒙的MIFARE Classic认证状态不跨Method Channel调用保持
            // 需要在每次写入前重新认证
            this.reauthenticateMifareClassic(mifareClassicTag, blockIndex)
              .then(() => {
                mifareClassicTag.writeSingleBlock(blockIndex, dataArray)
                  .then(() => {
                    console.log(`MIFARE Classic block ${blockIndex} write successful`);
                    result.success("");
                  })
                  .catch((error: ESObject) => {
                    console.error('MIFARE Classic block write failed:', error);
                    this.handleMifareError(error, "block write", result);
                  });
              })
              .catch((authError: ESObject) => {
                console.error('MIFARE Classic re-authentication failed before write:', authError);
                result.error("401", "MIFARE re-authentication failed - please authenticate first", authError?.message || authError?.toString() || 'Unknown error');
              });
          } else {
            // 如果鸿蒙官方API未实现，返回错误
            console.error('MIFARE Classic writeSingleBlock method not available in HarmonyOS API');
            result.error("405", "MIFARE Classic block write not supported on this platform", null);
          }
          return;
        }
      }

      // 检查MIFARE Ultralight标签
      if (this.TagInfo && this.TagInfo.technology.includes(tag.MIFARE_ULTRALIGHT)) {
        const mifareUltralightTag = this.getAndConnectMifareUltralight(result);
        if (mifareUltralightTag) {
          // MIFARE Ultralight使用页索引，验证页索引的有效性
          const ultralightType = mifareUltralightTag.getType();
          const mifareInfo = this.getMifareUltralightInfo(ultralightType);
          const maxPages = mifareInfo["blockCount"] as number;

          if (blockIndex < 0 || blockIndex >= maxPages) {
            result.error("400", `Invalid page index ${blockIndex}, should be in (0, ${maxPages})`, null);
            return;
          }

          // 验证数据大小（MIFARE Ultralight页大小为4字节）
          if (dataBytes.length !== 4) {
            result.error("400", `Invalid data size ${dataBytes.length}, should be 4 bytes for MIFARE Ultralight`, null);
            return;
          }

          // 使用鸿蒙官方API写入页数据
          if (typeof mifareUltralightTag.writeSinglePage === 'function') {
            // 转换Uint8Array为数组
            const dataArray = Array.from(dataBytes);
            mifareUltralightTag.writeSinglePage(blockIndex, dataArray)
              .then(() => {
                console.log(`MIFARE Ultralight page ${blockIndex} write successful`);
                result.success("");
              })
              .catch((error: ESObject) => {
                console.error('MIFARE Ultralight page write failed:', error);
                this.handleMifareError(error, "page write", result);
              });
          } else {
            // 如果鸿蒙官方API未实现，返回错误
            console.error('MIFARE Ultralight writeSinglePage method not available in HarmonyOS API');
            result.error("405", "MIFARE Ultralight page write not supported on this platform", null);
          }
          return;
        }
      }

      // 如果不是MIFARE标签，返回错误
      result.error("405", "Cannot invoke write on non-Mifare card", null);

    } catch (ex) {
      console.error('Error in performMifareBlockWrite:', ex);
      result.error("500", "Failed to perform MIFARE block write", ex.message || ex.toString());
    }
  }

  /**
   * 执行MIFARE Classic扇区读取操作
   * 参考Android版本的readSector实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#mifareclassictag
   *
   * 读取整个扇区的数据，包含该扇区内的所有块
   * 注意：不同扇区可能有不同数量的块（大多数是4块，但最后一个扇区可能有更多）
   */
  private performMifareSectorRead(sectorIndex: number, result: MethodResult): void {
    try {
      console.log(`Performing MIFARE Classic sector ${sectorIndex} read operation`);

      // 获取并连接 MIFARE Classic 标签（缓存过期安全）
      const mifareClassicTag = this.getAndConnectMifareClassic(result);
      if (!mifareClassicTag) {
        return; // 错误已通过 result 返回
      }

      // 验证扇区索引的有效性
      const maxSector = mifareClassicTag.getSectorCount();
      if (sectorIndex < 0 || sectorIndex >= maxSector) {
        result.error("400", `Invalid sector index ${sectorIndex}, should be in (0, ${maxSector})`, null);
        return;
      }

      // 获取扇区内的块索引范围（参考Android版本的sectorToBlock和getBlockCountInSector）
      const beginBlock = this.sectorToBlock(mifareClassicTag, sectorIndex);
      const blockCountInSector = mifareClassicTag.getBlockCountInSector(sectorIndex);
      const endBlock = beginBlock + blockCountInSector;

      console.log(`Reading sector ${sectorIndex}: blocks ${beginBlock} to ${endBlock - 1} (${blockCountInSector} blocks)`);

      // 逐个读取扇区内的所有块（参考Android版本的readSector实现）
      this.readSectorBlocks(mifareClassicTag, beginBlock, endBlock, result);

    } catch (ex) {
      console.error('Error in performMifareSectorRead:', ex);
      result.error("500", "Failed to perform MIFARE sector read", ex.message || ex.toString());
    }
  }

  /**
   * 读取扇区内的所有块并合并数据
   * 参考Android版本的readSector实现逻辑
   * 注意：鸿蒙的MIFARE Classic认证状态不跨Method Channel调用保持，
   * 需要先重新认证扇区再读取
   */
  private readSectorBlocks(mifareClassicTag: tag.MifareClassicTag, beginBlock: number, endBlock: number, result: MethodResult): void {
    const blockDataArray: number[][] = [];
    let completedReads = 0;
    const totalBlocks = endBlock - beginBlock;
    let hasError = false;

    // 用于合并所有块数据的函数
    const tryComplete = () => {
      if (hasError) return;
      if (completedReads === totalBlocks) {
        // 所有块都读取完成，合并数据
        let combinedData: number[] = [];
        for (let i = 0; i < totalBlocks; i++) {
          if (blockDataArray[i]) {
            combinedData = combinedData.concat(blockDataArray[i]);
          }
        }

        console.log(`MIFARE Classic sector read successful, total ${combinedData.length} bytes`);
        // 转换为Uint8Array格式返回（与Android版本一致）
        const uint8Data = new Uint8Array(combinedData);
        result.success(uint8Data);
      }
    };

    // 鸿蒙的MIFARE Classic认证状态不跨Method Channel调用保持
    // 需要在读取前重新认证
    this.reauthenticateMifareClassic(mifareClassicTag, beginBlock)
      .then(() => {
        // 逐个读取块（参考Android版本的for循环实现）
        for (let i = beginBlock; i < endBlock; i++) {
          const blockIndex = i;
          const arrayIndex = i - beginBlock;

          if (typeof mifareClassicTag.readSingleBlock === 'function') {
            mifareClassicTag.readSingleBlock(blockIndex)
              .then((data: number[]) => {
                if (hasError) return;
                console.log(`Block ${blockIndex} read successful, ${data.length} bytes`);
                blockDataArray[arrayIndex] = data;
                completedReads++;
                tryComplete();
              })
              .catch((error: ESObject) => {
                if (hasError) return;
                hasError = true;
                console.error(`Block ${blockIndex} read failed:`, error);
                this.handleMifareError(error, `sector ${this.blockToSector(mifareClassicTag, beginBlock)} block ${blockIndex} read`, result);
              });
          } else {
            // 如果鸿蒙官方API未实现，返回错误
            if (hasError) return;
            hasError = true;
            console.error('MIFARE Classic readSingleBlock method not available in HarmonyOS API');
            result.error("405", "MIFARE Classic sector read not supported on this platform", null);
            return;
          }
        }
      })
      .catch((authError: ESObject) => {
        if (hasError) return;
        hasError = true;
        console.error('MIFARE Classic re-authentication failed before sector read:', authError);
        result.error("401", "MIFARE re-authentication failed - please authenticate first", authError?.message || authError?.toString() || 'Unknown error');
      });
  }

  /**
   * 执行NFC数据透传操作
   * 参考Android版本的transceive实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#taggetndef9
   *
   * 支持的技术类型：IsoDep、NfcA、NfcB、NfcF、NfcV等
   * 支持APDU命令（ISO 7816）和原始命令（其他技术）
   */
  private performNfcTransceive(data: ESObject, timeout: number, result: MethodResult): void {
    try {
      console.log('Performing NFC transceive operation');

      // 数据标准化处理（支持字符串和字节数组）
      const inputIsString = typeof data === 'string';
      const sendingBytes = this.canonicalizeTransceiveData(data);

      if (!sendingBytes) {
        result.error("400", "Invalid data format", null);
        return;
      }

      const sendingHex = this.arrayToHexString(sendingBytes);
      console.log(`Transceive: ${sendingHex}`);

      // 根据标签技术类型选择相应的透传方法
      this.executeTransceive(sendingBytes, timeout, inputIsString, result);

    } catch (ex) {
      console.error('Error in performNfcTransceive:', ex);
      result.error("500", "Failed to perform NFC transceive", ex.message || ex.toString());
    }
  }

  /**
   * 执行具体的透传操作
   * 根据不同的NFC技术类型选择相应的API
   */
  private executeTransceive(sendingBytes: number[], timeout: number, inputIsString: boolean, result: MethodResult): void {
    if (!this.TagInfo) {
      result.error("406", "No tag available", null);
      return;
    }

    const techList = this.TagInfo.technology;

    // 优先尝试IsoDep（ISO 7816 APDU命令）
    if (techList.includes(tag.ISO_DEP)) {
      this.executeIsoDepTransceive(sendingBytes, timeout, inputIsString, result);
    }
    // 尝试NfcA技术
    else if (techList.includes(tag.NFC_A)) {
      this.executeNfcATransceive(sendingBytes, timeout, inputIsString, result);
    }
    // 尝试NfcB技术
    else if (techList.includes(tag.NFC_B)) {
      this.executeNfcBTransceive(sendingBytes, timeout, inputIsString, result);
    }
    // 尝试NfcF技术（FeliCa）
    else if (techList.includes(tag.NFC_F)) {
      this.executeNfcFTransceive(sendingBytes, timeout, inputIsString, result);
    }
    // 尝试NfcV技术（ISO 15693）
    else if (techList.includes(tag.NFC_V)) {
      this.executeNfcVTransceive(sendingBytes, timeout, inputIsString, result);
    }
    else {
      result.error("405", "Transceive not supported for this type of card", null);
    }
  }

  /**
   * 执行IsoDep（ISO 7816）透传
   * 主OAKAPDU命令透传
   */
  private executeIsoDepTransceive(sendingBytes: number[], timeout: number, inputIsString: boolean, result: MethodResult): void {
    try {
      const isoDepTag = tag.getIsoDep(this.TagInfo!);
      if (!isoDepTag) {
        result.error("406", "Failed to get IsoDep tag", null);
        return;
      }

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(isoDepTag, result)) {
        return;
      }

      // 使用鸿蒙官方API进行透传
      if (typeof isoDepTag.transmit === 'function') {
        // 设置超时时间（如果支持）
        this.setTransceiveTimeout(isoDepTag, timeout);

        isoDepTag.transmit(sendingBytes)
          .then((response: number[]) => {
            console.log(`IsoDep transceive successful, ${response.length} bytes received`);
            this.handleTransceiveResponse(response, inputIsString, result);
          })
          .catch((error: ESObject) => {
            console.error('IsoDep transceive failed:', error);
            this.handleTransceiveError(error, "IsoDep transceive", result);
          });
      } else {
        console.error('IsoDep transmit method not available in HarmonyOS API');
        result.error("405", "IsoDep transceive not supported on this platform", null);
      }
    } catch (ex) {
      console.error('Error in executeIsoDepTransceive:', ex);
      result.error("500", "Failed to execute IsoDep transceive", ex.message || ex.toString());
    }
  }

  /**
   * 执行NfcA透传
   */
  private executeNfcATransceive(sendingBytes: number[], timeout: number, inputIsString: boolean, result: MethodResult): void {
    try {
      const nfcATag = tag.getNfcA(this.TagInfo!);
      if (!nfcATag) {
        result.error("406", "Failed to get NfcA tag", null);
        return;
      }

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(nfcATag, result)) {
        return;
      }

      // 使用鸿蒙官方API进行透传
      if (typeof nfcATag.transmit === 'function') {
        this.setTransceiveTimeout(nfcATag, timeout);

        nfcATag.transmit(sendingBytes)
          .then((response: number[]) => {
            console.log(`NfcA transceive successful, ${response.length} bytes received`);
            this.handleTransceiveResponse(response, inputIsString, result);
          })
          .catch((error: ESObject) => {
            console.error('NfcA transceive failed:', error);
            this.handleTransceiveError(error, "NfcA transceive", result);
          });
      } else {
        console.error('NfcA transmit method not available in HarmonyOS API');
        result.error("405", "NfcA transceive not supported on this platform", null);
      }
    } catch (ex) {
      console.error('Error in executeNfcATransceive:', ex);
      result.error("500", "Failed to execute NfcA transceive", ex.message || ex.toString());
    }
  }

  /**
   * 执行NfcB透传
   */
  private executeNfcBTransceive(sendingBytes: number[], timeout: number, inputIsString: boolean, result: MethodResult): void {
    try {
      const nfcBTag = tag.getNfcB(this.TagInfo!);
      if (!nfcBTag) {
        result.error("406", "Failed to get NfcB tag", null);
        return;
      }

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(nfcBTag, result)) {
        return;
      }

      if (typeof nfcBTag.transmit === 'function') {
        this.setTransceiveTimeout(nfcBTag, timeout);

        nfcBTag.transmit(sendingBytes)
          .then((response: number[]) => {
            console.log(`NfcB transceive successful, ${response.length} bytes received`);
            this.handleTransceiveResponse(response, inputIsString, result);
          })
          .catch((error: ESObject) => {
            console.error('NfcB transceive failed:', error);
            this.handleTransceiveError(error, "NfcB transceive", result);
          });
      } else {
        console.error('NfcB transmit method not available in HarmonyOS API');
        result.error("405", "NfcB transceive not supported on this platform", null);
      }
    } catch (ex) {
      console.error('Error in executeNfcBTransceive:', ex);
      result.error("500", "Failed to execute NfcB transceive", ex.message || ex.toString());
    }
  }

  /**
   * 执行NfcF（FeliCa）透传
   */
  private executeNfcFTransceive(sendingBytes: number[], timeout: number, inputIsString: boolean, result: MethodResult): void {
    try {
      const nfcFTag = tag.getNfcF(this.TagInfo!);
      if (!nfcFTag) {
        result.error("406", "Failed to get NfcF tag", null);
        return;
      }

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(nfcFTag, result)) {
        return;
      }

      if (typeof nfcFTag.transmit === 'function') {
        this.setTransceiveTimeout(nfcFTag, timeout);

        nfcFTag.transmit(sendingBytes)
          .then((response: number[]) => {
            console.log(`NfcF transceive successful, ${response.length} bytes received`);
            this.handleTransceiveResponse(response, inputIsString, result);
          })
          .catch((error: ESObject) => {
            console.error('NfcF transceive failed:', error);
            this.handleTransceiveError(error, "NfcF transceive", result);
          });
      } else {
        console.error('NfcF transmit method not available in HarmonyOS API');
        result.error("405", "NfcF transceive not supported on this platform", null);
      }
    } catch (ex) {
      console.error('Error in executeNfcFTransceive:', ex);
      result.error("500", "Failed to execute NfcF transceive", ex.message || ex.toString());
    }
  }

  /**
   * 执行NfcV（ISO 15693）透传
   */
  private executeNfcVTransceive(sendingBytes: number[], timeout: number, inputIsString: boolean, result: MethodResult): void {
    try {
      const nfcVTag = tag.getNfcV(this.TagInfo!);
      if (!nfcVTag) {
        result.error("406", "Failed to get NfcV tag", null);
        return;
      }

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(nfcVTag, result)) {
        return;
      }

      if (typeof nfcVTag.transmit === 'function') {
        this.setTransceiveTimeout(nfcVTag, timeout);

        nfcVTag.transmit(sendingBytes)
          .then((response: number[]) => {
            console.log(`NfcV transceive successful, ${response.length} bytes received`);
            this.handleTransceiveResponse(response, inputIsString, result);
          })
          .catch((error: ESObject) => {
            console.error('NfcV transceive failed:', error);
            this.handleTransceiveError(error, "NfcV transceive", result);
          });
      } else {
        console.error('NfcV transmit method not available in HarmonyOS API');
        result.error("405", "NfcV transceive not supported on this platform", null);
      }
    } catch (ex) {
      console.error('Error in executeNfcVTransceive:', ex);
      result.error("500", "Failed to execute NfcV transceive", ex.message || ex.toString());
    }
  }

  /**
   * 处理透传响应数据
   * 确保返回类型与输入类型一致（与Android版本一致）
   */
  private handleTransceiveResponse(response: number[], inputIsString: boolean, result: MethodResult): void {
    try {
      if (inputIsString) {
        // 输入是字符串，返回十六进制字符串
        const hexResponse = this.arrayToHexString(response);
        console.log(`Transceive response (hex): ${hexResponse}`);
        result.success(hexResponse);
      } else {
        // 输入是字节数组，返回Uint8Array
        const uint8Response = new Uint8Array(response);
        console.log(`Transceive response (bytes): ${response.length} bytes`);
        result.success(uint8Response);
      }
    } catch (ex) {
      console.error('Error handling transceive response:', ex);
      result.error("500", "Failed to process transceive response", ex.message || ex.toString());
    }
  }

  /**
   * 处理透传错误
   */
  private handleTransceiveError(error: ESObject, operation: string, result: MethodResult): void {
    const errorMessage = this.extractErrorMessage(error);

    // 根据鸿蒙API文档的错误码返回相应的错误代码
    if (errorMessage.includes('3100201')) {
      result.error("503", `Tag running state is abnormal during ${operation}`, errorMessage);
    } else if (errorMessage.includes('3100204')) {
      result.error("500", `Tag I/O operation failed during ${operation}`, errorMessage);
    } else if (errorMessage.includes('401')) {
      result.error("400", "Parameter check failed", errorMessage);
    } else if (errorMessage.includes('201')) {
      result.error("403", "Permission denied", errorMessage);
    } else if (errorMessage.includes('timeout') || errorMessage.includes('408')) {
      result.error("408", `${operation} timeout`, errorMessage);
    } else if (errorMessage.includes('Communication') || errorMessage.includes('IOException')) {
      result.error("500", `Communication error during ${operation}`, errorMessage);
    } else if (errorMessage.includes('tag') && errorMessage.includes('removed')) {
      result.error("503", `Tag was removed during ${operation}`, errorMessage);
    } else if (errorMessage.includes('not supported') || errorMessage.includes('NoSuchMethodException')) {
      result.error("405", `${operation} not supported on this tag`, errorMessage);
    } else if (errorMessage.includes('format') || errorMessage.includes('command')) {
      result.error("400", "Command format error", errorMessage);
    } else {
      result.error("500", `${operation} operation failed`, errorMessage);
    }
  }

  /**
   * 设置透传超时时间
   * 参考Android版本的setTimeout实现
   */
  private setTransceiveTimeout(tagTech: ESObject, timeout: number): void {
    try {
      // 尝试设置超时时间（如果鸿蒙API支持）
      if (typeof tagTech.setTimeout === 'function') {
        tagTech.setTimeout(timeout);
        console.log(`Transceive timeout set to ${timeout}ms`);
      } else {
        console.warn('setTimeout method not available for this tag technology');
      }
    } catch (ex) {
      console.warn('Failed to set transceive timeout:', ex);
      // 不阻塞后续操作，只是警告
    }
  }

  /**
   * 数据标准化处理（透传专用）
   * 支持字符串（十六进制）和字节数组格式
   * 参考Android版本的canonicalizeData实现
   */
  private canonicalizeTransceiveData(data: ESObject): number[] | null {
    try {
      if (typeof data === 'string') {
        // 字符串格式（十六进制）
        return this.hexToBytes(data as string);
      } else if (data instanceof Uint8Array) {
        // Uint8Array格式
        return Array.from(data);
      } else if (Array.isArray(data)) {
        // 数组格式
        return data as number[];
      } else {
        console.error('Unsupported data type for transceive:', typeof data);
        return null;
      }
    } catch (ex) {
      console.error('Error canonicalizing transceive data:', ex);
      return null;
    }
  }

  /**
   * 将扇区索引转换为块索引
   * 参考Android版本的sectorToBlock实现
   */
  private sectorToBlock(mifareClassicTag: tag.MifareClassicTag, sectorIndex: number): number {
    try {
      // 使用鸿蒙API的getBlockCountInSector方法动态累加计算
      // 兼容1K（所有扇区各4块）和4K（扇区0-31各4块，扇区32-39各16块）标签
      let blockOffset = 0;
      for (let i = 0; i < sectorIndex; i++) {
        blockOffset += mifareClassicTag.getBlockCountInSector(i);
      }
      return blockOffset;
    } catch (e) {
      console.error('Error calculating sector to block:', e);
      throw new Error(`Failed to calculate sectorToBlock for sector ${sectorIndex}: ${e}`);
    }
  }

  /**
   * 处理MIFARE操作错误
   * 统一处理MIFARE Classic和Ultralight的错误
   */
  private handleMifareError(error: ESObject, operation: string, result: MethodResult): void {
    const errorMessage = this.extractErrorMessage(error);

    // 根据鸿蒙API文档的错误码返回相应的错误代码
    if (errorMessage.includes('3100201')) {
      result.error("503", `Tag running state is abnormal during ${operation}`, errorMessage);
    } else if (errorMessage.includes('3100204')) {
      result.error("500", `Tag I/O operation failed during ${operation}`, errorMessage);
    } else if (errorMessage.includes('401')) {
      result.error("400", "Parameter check failed", errorMessage);
    } else if (errorMessage.includes('201')) {
      result.error("403", "Permission denied", errorMessage);
    } else if (errorMessage.includes('Communication') || errorMessage.includes('IOException')) {
      result.error("500", `Communication error during ${operation}`, errorMessage);
    } else if (errorMessage.includes('tag') && errorMessage.includes('removed')) {
      result.error("503", `Tag was removed during ${operation}`, errorMessage);
    } else if (errorMessage.includes('not supported')) {
      result.error("405", `${operation} not supported on this tag`, errorMessage);
    } else if (errorMessage.includes('not authenticated') || errorMessage.includes('authentication')) {
      result.error("401", `Authentication required for ${operation}`, errorMessage);
    } else {
      result.error("500", `${operation} operation failed`, errorMessage);
    }
  }

  /**
   * 处理密钥数据的标准化
   * 参考Android版本的canonicalizeData实现
   * 支持字符串（十六进制）和字节数组格式
   */
  private canonicalizeKeyData(keyData: ESObject): number[] | null {
    try {
      if (keyData === null || keyData === undefined) {
        return null;
      }

      if (typeof keyData === 'string') {
        // 字符串格式（十六进制）
        const keyString = keyData as string;
        if (keyString.length === 0) {
          return null;
        }

        // 使用已有的hexToBytes方法转换
        return this.hexToBytes(keyString);

      } else if (Array.isArray(keyData)) {
        // 字节数组格式
        const keyArray = keyData as number[];
        if (keyArray.length === 0) {
          return null;
        }

        // 直接返回字节数组
        return keyArray;

      } else {
        console.error('Invalid key data format, expected string or number array');
        return null;
      }

    } catch (ex) {
      console.error('Error canonicalizing key data:', ex);
      return null;
    }
  }

  /**
   * 解析JSON数据为NDEF记录数组
   * 参考Android版本的记录解析逻辑
   */
  private parseJsonToNdefRecords(jsonData: string): Array<Record<string, ESObject>> {
    try {
      const recordsArray: ESObject = JSON.parse(jsonData);
      if (!Array.isArray(recordsArray)) {
        console.error('NDEF data is not an array');
        return [];
      }

      const validRecords: Array<Record<string, ESObject>> = [];

      let recordData: ESObject = '';
      for (recordData of recordsArray as Array<ESObject>) {
        try {
          // 验证记录数据的必要字段
          if (this.validateNdefRecordData(recordData)) {
            validRecords.push(recordData as Record<string, ESObject>);
          }
        } catch (recordError) {
          console.error('Error validating NDEF record:', recordError);
          // 继续处理其他记录
        }
      }

      return validRecords;

    } catch (ex) {
      console.error('Error parsing JSON to NDEF records:', ex);
      return [];
    }
  }

  /**
   * 验证NDEF记录数据的有效性
   */
  private validateNdefRecordData(recordData: ESObject): boolean {
    try {
      const record = recordData as Record<string, ESObject>;

      // 检查必要字段
      if (record.typeNameFormat === undefined ||
          record.type === undefined ||
          record.identifier === undefined ||
          record.payload === undefined) {
        console.error('Missing required NDEF record fields');
        return false;
      }

      // 检查TNF类型是否有效
      const tnf = this.convertStringToTnf(String(record.typeNameFormat));
      if (tnf === null) {
        console.error('Invalid TNF type:', record.typeNameFormat);
        return false;
      }

      return true;

    } catch (ex) {
      console.error('Error validating NDEF record data:', ex);
      return false;
    }
  }

  /**
   * 创建NDEF消息
   * 根据鸿蒙API创建标准的NdefMessage对象
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndefmessage9
   */
  private createNdefMessage(recordsData: Array<Record<string, ESObject>>): tag.NdefMessage {
    try {
      const ndefRecords: tag.NdefRecord[] = [];

      for (const recordData of recordsData) {
        try {
          const ndefRecord = this.createNdefRecord(recordData);
          if (ndefRecord) {
            ndefRecords.push(ndefRecord);
          }
        } catch (recordError) {
          console.error('Error creating NDEF record:', recordError);
          // 继续处理其他记录
        }
      }

      const ndefMessage: tag.NdefMessage = tag.ndef.createNdefMessage(ndefRecords);
      return ndefMessage;

    } catch (ex) {
      console.error('Error creating NDEF message:', ex);
      throw new Error(ex instanceof Error ? ex.message : String(ex));
    }
  }

  /**
   * 创建单个NDEF记录
   * 根据鸿蒙API创建标准的NdefRecord对象
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndefrecord9
   */
  private createNdefRecord(recordData: Record<string, ESObject>): tag.NdefRecord | null {
    try {
      // 转换TNF类型
      const tnf = this.convertStringToTnf(String(recordData.typeNameFormat));
      if (tnf === null) {
        console.error('Invalid TNF type for record creation');
        return null;
      }

      // 转换十六进制字符串为字节数组
      const type = this.hexToBytes(String(recordData.type));
      const identifier = this.hexToBytes(String(recordData.identifier));
      const payload = this.hexToBytes(String(recordData.payload));

      // 根据鸿蒙官方API创建记录对象
      // 注意：这里需要根据实际的鸿蒙API进行调整
      const ndefRecord: tag.NdefRecord = {
        tnf: tnf,
        rtdType: type,
        id: identifier,
        payload: payload
      } as tag.NdefRecord;

      return ndefRecord;

    } catch (ex) {
      console.error('Error creating NDEF record:', ex);
      return null;
    }
  }

  /**
   * 将Android兼容的字符串格式转换为鸿蒙TNF类型
   * 与convertTnfToString的逆向操作
   */
  private convertStringToTnf(tnfString: string): tag.TnfType | null {
    switch (tnfString) {
      case "empty":
        return tag.TnfType.TNF_EMPTY;
      case "nfcWellKnown":
        return tag.TnfType.TNF_WELL_KNOWN;
      case "media":
        return tag.TnfType.TNF_MEDIA;
      case "absoluteURI":
        return tag.TnfType.TNF_ABSOLUTE_URI;
      case "nfcExternal":
        return tag.TnfType.TNF_EXT_APP;
      case "unknown":
        return tag.TnfType.TNF_UNKNOWN;
      case "unchanged":
        return tag.TnfType.TNF_UNCHANGED;
      default:
        console.warn(`Unknown TNF string: ${tnfString}`);
        return null;
    }
  }
  /**
   * 参考Android版本的NDEF读取实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndeftagreadndef9
   */
  private performNdefRead(ndefTag: tag.NdefTag, cached: boolean, result: MethodResult): void {
    try {
      console.log('Performing NDEF read operation');

      // 确保标签已建立连接（鸿蒙API要求）
      if (!this.ensureTagConnected(ndefTag, result)) {
        return;
      }

      // 根据鸿蒙官方API文档，使用readNdef方法读取NDEF消息
      // 注意：鸿蒙的NDEF API可能与此接口不同，需要根据实际API进行调整
      if (typeof ndefTag.readNdef === 'function') {
        // 使用Promise处理异步操作
        ndefTag.readNdef()
          .then((ndefMessage: tag.NdefMessage) => {
            console.log('NDEF message read successfully');

            // 解析NDEF消息为与Android版本一致的格式
            const parsedRecords = this.parseNdefMessage(ndefMessage);
            const jsonResult = JSON.stringify(parsedRecords);

            console.log('NDEF read completed, records count:', parsedRecords.length);
            result.success(jsonResult);

          })
          .catch((error: ESObject) => {
            console.error('NDEF read failed:', error);
            const errorMessage = this.extractErrorMessage(error);

            // 根据错误类型返回相应的错误代码
            if (errorMessage.includes('Communication') || errorMessage.includes('IOException')) {
              result.error("500", "Communication error during NDEF read", errorMessage);
            } else if (errorMessage.includes('tag') && errorMessage.includes('removed')) {
              result.error("503", "Tag was removed during NDEF read", errorMessage);
            } else if (errorMessage.includes('not supported')) {
              result.error("405", "NDEF read not supported on this tag", errorMessage);
            } else {
              result.error("500", "NDEF read operation failed", errorMessage);
            }
          });

      } else {
        // 如果鸿蒙官方API未实现，返回错误
        console.error('NDEF readNdef method not available in HarmonyOS API');
        result.error("405", "NDEF read not supported on this platform", null);
      }

    } catch (ex) {
      console.error('Error in performNdefRead:', ex);
      result.error("500", "Failed to perform NDEF read", ex.message || ex.toString());
    }
  }

  /**
   * 解析NDEF消息为与Android版本一致的格式
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndefmessage9
   */
  private parseNdefMessage(ndefMessage: tag.NdefMessage): Array<Record<string, ESObject>> {
    const parsedRecords: Array<Record<string, ESObject>> = [];

    try {
      // 根据鸿蒙官方API文档，NdefMessage包含NdefRecord数组
      if (ndefMessage && ndefMessage.getNdefRecords() && Array.isArray(ndefMessage.getNdefRecords())) {
        for (const record of ndefMessage.getNdefRecords()) {
          try {
            const parsedRecord = this.parseNdefRecord(record);
            parsedRecords.push(parsedRecord);
          } catch (recordError) {
            console.error('Error parsing NDEF record:', recordError);
            // 继续处理其他记录，不要因为一个记录错误就失败
          }
        }
      }

    } catch (ex) {
      console.error('Error parsing NDEF message:', ex);
    }

    return parsedRecords;
  }

  /**
   * 解析单个NDEF记录
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#ndefrecord9
   */
  private parseNdefRecord(record: tag.NdefRecord): Record<string, ESObject> {
    try {
      // 根据鸿蒙官方API文档解析NDEF记录字段
      const identifier = record.id ? this.arrayToHexString(record.id) : "";
      const payload = record.payload ? this.arrayToHexString(record.payload) : "";
      const type = record.rtdType ? this.arrayToHexString(record.rtdType) : "";

      // 将鸿蒙的TNF类型转换为与Android一致的格式
      const typeNameFormat = this.convertTnfToString(record.tnf);

      return {
        "identifier": identifier,
        "payload": payload,
        "type": type,
        "typeNameFormat": typeNameFormat
      };

    } catch (ex) {
      console.error('Error parsing individual NDEF record:', ex);
      // 返回一个空的记录作为降级处理
      return {
        "identifier": "",
        "payload": "",
        "type": "",
        "typeNameFormat": "unknown"
      };
    }
  }

  /**
   * 将鸿蒙TNF类型转换为与Android一致的字符串格式
   * 根据鸿蒙官方API文档的TNF类型枚举进行映射
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#tnftype9
   *
   * 官方枚举定义：
   * - TNF_EMPTY = 0x0
   * - TNF_WELL_KNOWN = 0x1
   * - TNF_MEDIA = 0x2
   * - TNF_ABSOLUTE_URI = 0x3
   * - TNF_EXT_APP = 0x4 (对应Android的TNF_EXTERNAL_TYPE)
   * - TNF_UNKNOWN = 0x5
   * - TNF_UNCHANGED = 0x6
   */
  private convertTnfToString(tnf: tag.TnfType): string {
    // 根据鸿蒙官方API文档的TNF类型枚举进行映射
    switch (tnf) {
      case tag.TnfType.TNF_EMPTY:
        return "empty";
      case tag.TnfType.TNF_WELL_KNOWN:
        return "nfcWellKnown";
      case tag.TnfType.TNF_MEDIA:
        return "media";
      case tag.TnfType.TNF_ABSOLUTE_URI:
        return "absoluteURI";
      case tag.TnfType.TNF_EXT_APP:
        return "nfcExternal"; // 鸿蒙的TNF_EXT_APP对应Android的TNF_EXTERNAL_TYPE
      case tag.TnfType.TNF_UNKNOWN:
        return "unknown";
      case tag.TnfType.TNF_UNCHANGED:
        return "unchanged";
      default:
        console.warn(`Unknown TNF type: ${tnf}, using 'unknown'`);
        return "unknown";
    }
  }

  /**
   * 提取错误信息的辅助方法
   */
  private extractErrorMessage(error: ESObject): string {
    try {
      if (error instanceof Error) {
        return error.message || error.toString();
      } else if (typeof error === 'string') {
        return error;
      } else if (error && typeof error === 'object') {
        // 尝试从错误对象中提取有用信息
        const errorObj = error as Record<string, ESObject>;
        if (errorObj.message) {
          return String(errorObj.message);
        } else if (errorObj.code) {
          return `Error code: ${errorObj.code}`;
        } else {
          return JSON.stringify(error);
        }
      } else {
        return String(error);
      }
    } catch (ex) {
      return 'Failed to extract error message';
    }
  }

  /**
   * 轮询NFC标签
   * 参考Android版本的pollTag实现，使用鸿蒙NFC API
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfccontroller#nfcstate
   *       https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag#taggetndef9
   */
  private pollTag(result: AsyncMethodResult, timeout: number, technologies: number): void {
    try {
      // 检查NFC是否可用
      if (!nfcController.isNfcOpen()) {
        result.error("404", "NFC not available", null);
        return;
      }

      // 状态机守卫：如果不在IDLE状态，先清理旧状态再开始新的poll
      // 注意：不能用cancelPending=true，因为当前poll的result已经注册在pendingResults中了，
      // cancelPending=true会把当前poll的result也取消掉，导致503错误
      if (this.sessionState !== NfcSessionState.IDLE) {
        console.warn(`pollTag: current state is ${NfcSessionState[this.sessionState]}, forcing cleanup to IDLE (preserving current poll result)`);
        this.transitionTo(NfcSessionState.IDLE, false);
      }

      // 根据Flutter端传入的technologies bitmask，构建鸿蒙discTech列表
      const discTech: number[] = this.buildDiscTechFromBitmask(technologies);
      console.log(`pollTag: technologies bitmask=${technologies}, discTech=${discTech}`);

      // poll时注册readerMode（与Android的enableReaderMode一致）
      if (this.registeredDiscTech === null || !this.arraysEqual(this.registeredDiscTech, discTech)) {
        console.log(`pollTag: registering readerMode with discTech=${discTech}`);
        this.registerReaderMode(discTech);
      }

      // 检查registerReaderMode是否成功
      if (!this.foregroundRegister) {
        console.error('pollTag: readerMode registration failed, cannot proceed');
        result.error('500', 'Failed to register readerMode', null);
        return;
      }

      // 取消待执行的后台注销延迟（如果App刚从后台切回前台并立即poll）
      if (this.backgroundUnregisterTimerId !== null) {
        clearTimeout(this.backgroundUnregisterTimerId);
        this.backgroundUnregisterTimerId = null;
        console.log('pollTag: cancelled pending background unregister (app returned to foreground)');
      }

      // 状态转换：IDLE → POLLING（清理旧的标签状态）
      this.transitionTo(NfcSessionState.POLLING);

      // 设置超时定时器（超时后transitionTo IDLE + cancel pending results）
      this.pollingTimeoutId = setTimeout(() => {
        console.log('pollTag: timeout reached, transitioning to IDLE');
        result.error("408", "Polling tag timeout", null);
        this.transitionTo(NfcSessionState.IDLE, true);
      }, timeout);

      // 设置NFC状态变化监听器
      this.nfcStateChangeCallback = (state: nfcController.NfcState) => {
        console.log(`NFC state changed: ${state}`);
        if (state !== nfcController.NfcState.STATE_ON && this.sessionState === NfcSessionState.POLLING) {
          result.error("404", "NFC was disabled during polling", `NFC state: ${state}`);
          this.transitionTo(NfcSessionState.IDLE, true);
        }
      };
      nfcController.on('nfcStateChange', this.nfcStateChangeCallback);

      console.log('Polling state set - waiting for readerMode callback to trigger handleTagDetected');

    } catch (ex) {
      console.error("Error in pollTag:", ex);
      result.error("500", "Failed to start polling", ex.message || ex.toString());
    }
  }



  /**
   * 处理检测到的标签 —— 状态机驱动版本
   */
  private handleTagDetected(tagInfo: tag.TagInfo): void {
    try {
      // 状态机守卫：只有POLLING状态才处理标签
      if (this.sessionState !== NfcSessionState.POLLING) {
        console.warn(`handleTagDetected: ignoring tag in state ${NfcSessionState[this.sessionState]}`);
        return;
      }

      console.log("NFC tag detected:", tagInfo);

      // 获取poll时注册的pending result
      let pollResult: AsyncMethodResult | null = null;
      for (const ar of this.pendingResults) {
        if (!ar.isSettled()) {
          pollResult = ar;
          break;
        }
      }

      if (!pollResult) {
        console.warn('handleTagDetected: no pending polling result available, transitioning to IDLE');
        this.transitionTo(NfcSessionState.IDLE, true);
        return;
      }

      // 状态转换：POLLING → TAG_CONNECTED（取消超时定时器，保留标签数据）
      this.transitionTo(NfcSessionState.TAG_CONNECTED);

      // 解析标签信息
      let jsonResult: string;
      try {
        jsonResult = this.parseTag(tagInfo);
        if (!jsonResult || jsonResult === '{}') {
          throw new Error('parseTag returned empty or invalid result');
        }
      } catch (parseError) {
        pollResult.error("500", "Failed to parse tag data", parseError?.message || parseError?.toString() || 'Unknown parse error');
        return;
      }

      // 返回结果
      pollResult.success(jsonResult);

    } catch (ex) {
      console.error("Error handling detected tag:", ex);
      for (const ar of this.pendingResults) {
        if (!ar.isSettled()) {
          ar.error("500", "Failed to process detected tag", ex?.message || ex?.toString() || 'Unknown error');
          break;
        }
      }
      this.transitionTo(NfcSessionState.IDLE, true);
    }
  }

  /**
   * 处理轮询错误 —— 状态机驱动版本
   */
  private handlePollingError(code: string, message: string, details: string | null): void {
    for (const ar of this.pendingResults) {
      if (!ar.isSettled()) {
        ar.error(code, message, details);
        break;
      }
    }
    this.transitionTo(NfcSessionState.IDLE, true);
  }

  /**
   * 将十六进制字符串转换为字节数组
   * 参考Android版本的hexToBytes实现
   */
  private hexToBytes(hexString: string): number[] {
    try {
      if (!hexString || hexString.length === 0) {
        return [];
      }

      // 去除可能的空格和分隔符
      const cleanHex = hexString.replace(/[\s-:]/g, '');

      // 确保长度为偶数
      const paddedHex = cleanHex.length % 2 === 0 ? cleanHex : '0' + cleanHex;

      const bytes: number[] = [];
      for (let i = 0; i < paddedHex.length; i += 2) {
        const hexByte = paddedHex.substr(i, 2);
        bytes.push(parseInt(hexByte, 16));
      }

      return bytes;
    } catch (ex) {
      console.error('Error converting hex string to bytes:', ex);
      return [];
    }
  }

  /**
   * 完成NFC操作，清理所有资源
   * 参考Android版本的finish实现
   * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfccontroller
   *       https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-nfctag
   */
  private finishNfcOperations(result: MethodResult): void {
    try {
      console.log("Starting NFC operations cleanup");

      // 先让finish的result成功返回（settled后不会被cancelAllPendingResults影响）
      result.success("");

      // 取消后台注销延迟定时器
      if (this.backgroundUnregisterTimerId !== null) {
        clearTimeout(this.backgroundUnregisterTimerId);
        this.backgroundUnregisterTimerId = null;
      }

      // 状态机驱动：transitionTo IDLE 执行统一清理，cancelPending=true 取消其他异步操作
      this.transitionTo(NfcSessionState.IDLE, true);

      console.log("NFC operations cleanup completed");

    } catch (ex) {
      console.error("Error during NFC operations cleanup:", ex);
      // finish的result已经settled，不能再次调用
      // transitionTo会在catch外继续执行或由下次调用触发
    }
  }

  /**
   * 发送缓存的NFC标签数据
   * 在EventSink初始化后调用，将后台到达时缓存的数据发送给Flutter层
   */
  private deliverPendingTagData(): void {
    if (this.pendingTagData && this.eventSink && this.isEventSinkReady) {
      try {
        console.log('Delivering pending tag data to Flutter layer');
        this.eventSink.success(this.pendingTagData);
        this.pendingTagData = null;
        console.log('Pending tag data delivered successfully');
      } catch (error) {
        console.error('Error delivering pending tag data:', error);
        this.pendingTagData = null;
      }
    }
  }

  /**
   * 重试发送缓存的NFC标签数据
   * 使用延迟机制等待EventSink初始化就绪
   */
  private retryPendingTagDelivery(maxWaitTime: number): void {
    let retryCount = 0;
    const maxRetries = Math.max(1, Math.floor(maxWaitTime / 500));
    const retryInterval = setInterval(() => {
      retryCount++;

      if (this.eventSink && this.isEventSinkReady && this.pendingTagData) {
        this.deliverPendingTagData();
        clearInterval(retryInterval);
      } else if (retryCount >= maxRetries) {
        console.warn(`Failed to deliver pending tag data after ${maxWaitTime}ms, giving up`);
        this.pendingTagData = null;
        clearInterval(retryInterval);
      } else {
        console.log(`Retrying pending tag delivery (${retryCount}/${maxRetries})`);
      }
    }, 500);
  }

  /**
   * 将Flutter端传入的technologies bitmask转换为鸿蒙discTech数组
   *
   * Flutter端的bitmask定义（对应android.nfc.NfcAdapter.FLAGS）:
   *   0x1 = readIso14443A → tag.NFC_A
   *   0x2 = readIso14443B → tag.NFC_B
   *   0x4 = readIso18092  → tag.NFC_F
   *   0x8 = readIso15693  → tag.NFC_V
   *
   * 如果bitmask为0（用户未指定任何标签类型），默认检测所有主流类型
   */
  private buildDiscTechFromBitmask(technologies: number): number[] {
    const discTech: number[] = [];
    if ((technologies & 0x1) !== 0) {
      discTech.push(tag.NFC_A);
    }
    if ((technologies & 0x2) !== 0) {
      discTech.push(tag.NFC_B);
    }
    if ((technologies & 0x4) !== 0) {
      discTech.push(tag.NFC_F);
    }
    if ((technologies & 0x8) !== 0) {
      discTech.push(tag.NFC_V);
    }
    // 如果用户未指定任何标签类型，默认检测所有主流类型
    if (discTech.length === 0) {
      discTech.push(tag.NFC_A, tag.NFC_B, tag.NFC_F, tag.NFC_V);
      console.log('buildDiscTechFromBitmask: no technologies specified, using defaults (NFC_A/B/F/V)');
    }
    return discTech;
  }

  /**
   * 比较两个number数组是否相等（用于判断discTech是否需要更新）
   */
  private arraysEqual(a: number[] | null, b: number[]): boolean {
    if (a === null || a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

}

/** 异步MethodResult包装 —— 统一settled标记 + cancel机制，替代MethodResultWrapper_Internal */
class AsyncMethodResult implements MethodResult {
  private result: MethodResult;
  private settled: boolean = false;
  /** settled时自动从pendingResults中移除的回调 */
  private onSettledCallback: (() => void) | null = null;

  constructor(result: MethodResult) {
    this.result = result;
  }

  /** 设置settled回调（由FlutterNfcKitPlugin.registerPendingResult调用） */
  setOnSettled(callback: () => void): void {
    this.onSettledCallback = callback;
  }

  private markSettled(): void {
    this.settled = true;
    if (this.onSettledCallback !== null) {
      try {
        this.onSettledCallback();
      } catch (e) {
        console.error('AsyncMethodResult: exception in onSettled callback:', e);
      }
    }
  }

  success(data: ESObject): void {
    if (this.settled) {
      console.warn('AsyncMethodResult: result already settled, ignoring success call');
      return;
    }
    this.markSettled();
    try {
      this.result.success(data);
    } catch (e) {
      console.error('AsyncMethodResult: exception in result.success:', e);
    }
  }

  error(errorCode: string, errorMessage: string, errorDetails: ESObject): void {
    if (this.settled) {
      console.warn('AsyncMethodResult: result already settled, ignoring error call');
      return;
    }
    this.markSettled();
    try {
      this.result.error(errorCode, errorMessage, errorDetails);
    } catch (e) {
      console.error('AsyncMethodResult: exception in result.error:', e);
    }
  }

  notImplemented(): void {
    if (this.settled) {
      console.warn('AsyncMethodResult: result already settled, ignoring notImplemented call');
      return;
    }
    this.markSettled();
    try {
      this.result.notImplemented();
    } catch (e) {
      console.error('AsyncMethodResult: exception in result.notImplemented:', e);
    }
  }

  /** 会话取消时自动返回503错误，解决"异步操作期间用户调用finish"的问题 */
  cancel(reason: string): void {
    if (this.settled) {
      return;
    }
    this.markSettled();
    try {
      this.result.error("503", reason, null);
    } catch (e) {
      console.error('AsyncMethodResult: exception in cancel:', e);
    }
  }

  isSettled(): boolean {
    return this.settled;
  }
}