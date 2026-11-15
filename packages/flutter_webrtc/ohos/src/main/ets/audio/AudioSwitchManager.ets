/* MIT License
*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
* All rights reserved.
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import { audio } from '@kit.AudioKit';
import { Any, Log } from '@ohos/flutter_ohos';
import { JSON } from '@kit.ArkTS';
import { DataMap, ObjectType } from '../utils/ObjectType';
import {
  AudioCapturerSamplesReadyEvent,
  AudioDeviceModule,
  AudioDeviceModuleOptions,
  AudioErrorEvent,
  AudioStateChangeEvent
} from 'libohos_webrtc.so';
import { isNotEmpty } from '../utils/Utils';
import { ConstraintsMap } from '../utils/ConstraintsMap';
import { BusinessError } from '@kit.BasicServicesKit';
import deviceInfo from '@ohos.deviceInfo';

const TAG = 'AudioSwitchManager'

export default class AudioSwitchManager {
  public static instance: AudioSwitchManager;
  private audioManager: audio.AudioManager;
  private audioRoutingManager: audio.AudioRoutingManager;
  private audioRenderer: audio.AudioRenderer | null = null;
  private audioCapturer: audio.AudioCapturer | null = null;
  private isActive: boolean = false;
  private context?: Context;
  private adm?: AudioDeviceModule;
  private audioStreamInfo: audio.AudioStreamInfo = {
    samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
    channels: audio.AudioChannel.CHANNEL_2,
    sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
    encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
  };
  private audioRendererInfo: audio.AudioRendererInfo = {
    usage: audio.StreamUsage.STREAM_USAGE_UNKNOWN,
    rendererFlags: 0
  };
  private audioCapturerInfo: audio.AudioCapturerInfo = {
    source: audio.SourceType.SOURCE_TYPE_MIC,
    capturerFlags: 0
  };

  constructor() {
    this.audioManager = audio.getAudioManager();
    this.audioRoutingManager = this.audioManager.getRoutingManager();
    // The actual WebRTC ADM owns capture/playout; do not open extra devices at plugin attach.
  }

  public static getInstance(): AudioSwitchManager {
    if (!AudioSwitchManager.instance) {
      AudioSwitchManager.instance = new AudioSwitchManager();
    }
    return AudioSwitchManager.instance;
  }

  setContext(context: Context) {
    this.context = context;
  }

  getAudioDeviceModule(): AudioDeviceModule | undefined {
    return this.adm;
  }

  async createAudioRenderer() {
    this.audioRenderer = null;
    let audioRendererOptions: audio.AudioRendererOptions = {
      streamInfo: this.audioStreamInfo,
      rendererInfo: this.audioRendererInfo
    };
    try {
      this.audioRenderer = await audio.createAudioRenderer(audioRendererOptions);
      this.onAudioInterrupt();
    } catch (e) {
      Log.e(TAG, 'createAudioRenderer error , msg: ' + JSON.stringify(e));
    }
  }

  async createAudioCapturer() {
    this.audioCapturer = null;
    let audioCapturerOptions: audio.AudioCapturerOptions = {
      streamInfo: this.audioStreamInfo,
      capturerInfo: this.audioCapturerInfo
    };
    try {
      this.audioCapturer = await audio.createAudioCapturer(audioCapturerOptions);
    } catch (e) {
      Log.e(TAG, 'createAudioCapturer error , msg: ' + JSON.stringify(e));
    }
  }

  createAudioDeviceModule(): void {
    this.adm = new AudioDeviceModule({
      useStereoInput: true,
      useStereoOutput: true,
      useHardwareAcousticEchoCanceler: true,
      useHardwareNoiseSuppressor: true
    } as AudioDeviceModuleOptions);
    this.adm.oncapturererror = (event: AudioErrorEvent) => {
      Log.e(TAG, 'oncapturererror: ' + JSON.stringify(event));
    };
    this.adm.oncapturerstatechange = (event: AudioStateChangeEvent) => {
      Log.e(TAG, 'oncapturerstatechange: ' + JSON.stringify(event));
    };
    this.adm.onrenderererror = (event: AudioErrorEvent) => {
      Log.e(TAG, 'onrenderererror: ' + JSON.stringify(event));
    };
    this.adm.onrendererstatechange = (event: AudioStateChangeEvent) => {
      Log.e(TAG, 'onrendererstatechange: ' + JSON.stringify(event));
    };
    Log.d(TAG, 'this.adm: ' + JSON.stringify(this.adm));
  }

  start() {
    this.audioRenderer?.start().then(() => {
      Log.d(TAG, 'Renderer started');
      this.isActive = true;
    }).catch((err: BusinessError) => {
      Log.e(TAG, `Renderer started ERROR: ${err}`);
    });
  }

  stop() {
    Log.d(TAG, 'Stopping the audio manager...');
    this.audioRenderer?.stop().then(() => {
      Log.d(TAG, 'Renderer stopped');
      this.isActive = false;
    }).catch((err: BusinessError) => {
      Log.e(TAG, `Renderer stopped ERROR: ${err}`);
    });
  }

  setMicrophoneMute(mute: boolean) {
    this.adm?.setMicrophoneMute(mute);
  }

  getAudioOutputDevices() {
    return this.audioRoutingManager?.getDevicesSync(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
  }

  getAllAudioDevices() {
    return this.audioRoutingManager?.getDevicesSync(audio.DeviceFlag.ALL_DEVICES_FLAG);
  }

  async selectAudioOutput(deviceId: number): Promise<void> {
    const device = this.getAudioOutputDevices()?.find((item: audio.AudioDeviceDescriptor): boolean => item.id === deviceId);
    if (!device) throw new Error('Audio output device not found');
    await this.setCommunicationDevice(device.deviceType);
  }
  async selectAudioInput(deviceId: string): Promise<void> {
    if (deviceInfo.sdkApiVersion < 26) throw new Error('Explicit audio input selection requires OHOS API 26');
    const manager = this.audioManager.getDeviceEnhanceManager();
    if (!manager.isEnhancedRoutingSupported()) throw new Error('Enhanced audio input routing is unavailable on this device');
    const devices = this.audioRoutingManager.getAvailableDevices(audio.DeviceUsage.CALL_INPUT_DEVICES);
    const device = devices.find((item: audio.AudioDeviceDescriptor): boolean => item.id.toString() === deviceId);
    if (!device) throw new Error('Audio input device not found');
    await manager.selectInputDevice(device);
  }
  async setCommunicationDevice(deviceType: number): Promise<void> {
    if (this.audioRoutingManager == null) throw new Error('Audio routing manager unavailable');
    await this.audioRoutingManager.setCommunicationDevice(deviceType, true);
  }
  async enableSpeakerphone(enable: boolean): Promise<void> {
    if (enable) { await this.setCommunicationDevice(audio.DeviceType.SPEAKER); return; }
    const devices = this.getAudioOutputDevices();
    if (!devices || devices.length === 0) throw new Error('No audio output devices');
    const device = devices.find((item: audio.AudioDeviceDescriptor): boolean => item.deviceType !== audio.DeviceType.SPEAKER);
    await this.setCommunicationDevice(device?.deviceType ?? devices[0].deviceType);
  }
  async enableSpeakerButPreferBluetooth(): Promise<void> {
    const devices = this.getAudioOutputDevices();
    if (!devices || devices.length === 0) throw new Error('No audio output devices');
    const device = devices.find((item: audio.AudioDeviceDescriptor): boolean => item.deviceType === audio.DeviceType.BLUETOOTH_SCO ||
      item.deviceType === audio.DeviceType.WIRED_HEADSET);
    await this.setCommunicationDevice(device?.deviceType ?? audio.DeviceType.SPEAKER);
  }

  setAudioConfiguration(configuration: ConstraintsMap) {
    const setConfig = (key: string, type: ObjectType, setter: (value: Any) => void) => {
      let value: Any = null;
      if (configuration.getType(key) === type) {
        value = configuration.get(key);
      }
      if (isNotEmpty(value)) {
        setter(value);
      }
    };

    setConfig('ohosStreamUsage', ObjectType.String, (value: string) => this.setStreamUsage(value));
    setConfig('ohosSourceType', ObjectType.String, (value: string) => this.setSourceType(value));

    this.createAudioRenderer();
    this.createAudioCapturer();
  }

  setStreamUsage(value: string): void {
    let streamUsageMap: Map<string, audio.StreamUsage> = new Map([
      ['unknown', audio.StreamUsage.STREAM_USAGE_UNKNOWN],
      ['music', audio.StreamUsage.STREAM_USAGE_MUSIC],
      ['voiceCommunication', audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION],
      ['voiceAssistant', audio.StreamUsage.STREAM_USAGE_VOICE_ASSISTANT],
      ['alarm', audio.StreamUsage.STREAM_USAGE_ALARM],
      ['voiceMessage', audio.StreamUsage.STREAM_USAGE_VOICE_MESSAGE],
      ['ringtone', audio.StreamUsage.STREAM_USAGE_RINGTONE],
      ['notification', audio.StreamUsage.STREAM_USAGE_NOTIFICATION],
      ['accessibility', audio.StreamUsage.STREAM_USAGE_ACCESSIBILITY],
      ['movie', audio.StreamUsage.STREAM_USAGE_MOVIE],
      ['game', audio.StreamUsage.STREAM_USAGE_GAME],
      ['audioBook', audio.StreamUsage.STREAM_USAGE_AUDIOBOOK],
      ['navigation', audio.StreamUsage.STREAM_USAGE_NAVIGATION],
      ['videoCommunication', audio.StreamUsage.STREAM_USAGE_VIDEO_COMMUNICATION]
    ]);
    let streamUsage = streamUsageMap.get(value);
    if (streamUsage != undefined) {
      this.audioRendererInfo.usage = streamUsage;
    }
  }

  setSourceType(value: string): void {
    let sourceTypeMap: Map<string, audio.SourceType> = new Map([
      ['invalid', audio.SourceType.SOURCE_TYPE_INVALID],
      ['mic', audio.SourceType.SOURCE_TYPE_MIC],
      ['voiceRecognition', audio.SourceType.SOURCE_TYPE_VOICE_RECOGNITION],
      ['voiceCommunication', audio.SourceType.SOURCE_TYPE_VOICE_COMMUNICATION],
      ['voiceMessage', audio.SourceType.SOURCE_TYPE_VOICE_MESSAGE],
      ['camcorder', audio.SourceType.SOURCE_TYPE_CAMCORDER]
    ]);
    let sourceType = sourceTypeMap.get(value);
    if (sourceType != undefined) {
      this.audioCapturerInfo.source = sourceType;
    }
  }

  /**
   * 音频打断事件监听
   * AudioRenderer对象在start事件发生时会主动获取焦点，在pause、stop等事件发生时会主动释放焦点
   */
  async onAudioInterrupt() {
    this.audioRenderer?.on('audioInterrupt', (interruptEvent: audio.InterruptEvent) => {
      // 在发生音频打断事件时，audioRenderer收到interruptEvent回调，此处可根据其内容做相应处理。
      // 1、可选：读取interruptEvent.forceType的类型，判断系统是否已强制执行相应操作。
      // 2、必选：读取interruptEvent.hintType的类型，做出相应的处理。
      Log.d(TAG, `onAudioInterrupt: interruptEvent.forceType=${interruptEvent.forceType}`);
      Log.d(TAG, `onAudioInterrupt: interruptEvent.hintType=${interruptEvent.hintType}`);
    });
  }

  /**
   * 当前发声设备切换回调监听
   */
  async onPreferOutputDeviceChangeForRendererInfo() {
    this.audioRoutingManager?.on('preferOutputDeviceChangeForRendererInfo', this.audioRendererInfo,
      (desc: audio.AudioDeviceDescriptors) => {
        Log.d(TAG, `onPreferOutputDeviceChangeForRendererInfo device change To : ${desc[0].deviceType}`);
      });
  }
}
