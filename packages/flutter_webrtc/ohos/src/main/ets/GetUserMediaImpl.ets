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

import StateProvider from './StateProvider';
import { Log, MethodResult, SurfaceTextureEntry } from '@ohos/flutter_ohos';
import { ConstraintsMap } from './utils/ConstraintsMap';
import { ConstraintsArray } from './utils/ConstraintsArray';
import webrtc, {
  AudioSource,
  AudioTrack,
  MediaStream,
  PeerConnectionFactory,
  VideoSource,
  VideoTrack
} from 'libohos_webrtc.so';
import { HashMap } from '@kit.ArkTS';
import { ObjectType } from './utils/ObjectType';
import AudioSwitchManager from './audio/AudioSwitchManager';
import {
  beginConfig,
  getCameraDevices,
  getCameraInput,
  getCameraManager,
  getCaptureSession,
  getPreviewOutput,
  getSupportedOutputCapability,
  isTorchSupported,
  setSessionCameraInput,
  setSessionPreviewOutput,
  setTorchMode,
  setZoom,
  startSession,
  switchCamera
} from './utils/CameraUtil';
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

const TAG: string = 'FlutterWebRTCPlugin-GetUserMediaImpl';

export default class GetUserMediaImpl {
  private static DEFAULT_WIDTH: number = 1280;
  private static DEFAULT_HEIGHT: number = 720;
  private static DEFAULT_FPS: number = 30;
  private static PERMISSION_AUDIO: string = '';
  private static PERMISSION_VIDEO: string = '';
  private static PERMISSION_SCREEN: string = '';
  private static CAPTURE_PERMISSION_REQUEST_CODE: number = 1;
  private static GRANT_RESULTS: string = 'GRANT_RESULT';
  private static PERMISSIONS: string = 'PERMISSION';
  private static PROJECTION_DATA: string = 'PROJECTION_DATA';
  private static RESULT_RECEIVER: string = 'RESULT_RECEIVER';
  private static REQUEST_CODE: string = 'REQUEST_CODE';
  // private mVideoCapturers: HashMap<String, VideoCapturerInfo> = new HashMap();
  // private mSurfaceTextureHelpers: HashMap<String, SurfaceTextureHelper> = new HashMap();
  private stateProvider: StateProvider | null = null;
  private applicationContext: Context | null = null;
  private isFacing: boolean = true;
  private isTorchOn: boolean = false;
  private surfaceTextureEntry: SurfaceTextureEntry | null = null;

  constructor(stateProvider: StateProvider, applicationContext: Context) {
    this.stateProvider = stateProvider
    this.applicationContext = applicationContext
    getCameraManager(getContext() as common.BaseContext);
  }

  setSurfaceTextureEntry(surfaceTextureEntry: SurfaceTextureEntry | null) {
    this.surfaceTextureEntry = surfaceTextureEntry;
  }

  resultError(method: string, error: string, result: MethodResult) {
    let errorMsg: string = method + '(): ' + error;
    result.error(method, errorMsg, null);
    Log.d(TAG, errorMsg);
  }

  getUserMedia(constraints: ConstraintsMap, result: MethodResult, mediaStream: MediaStream) {
    Log.d(TAG, 'getUserMedia in!');

    /*
     * 这里的作用是获取media的 streamId audioTracks videoTracks
     *
     * */
    let trackParams: ConstraintsMap[] = [new ConstraintsMap(), new ConstraintsMap()];

    trackParams[0] = this.getUserAudio(constraints, mediaStream)
    trackParams[1] = this.getUserVideo(constraints, mediaStream)

    let audioTracks: ConstraintsArray = new ConstraintsArray();
    let videoTracks: ConstraintsArray = new ConstraintsArray();
    let successResult: ConstraintsMap = new ConstraintsMap();

    for (let i = 0; i < trackParams.length; i++) {
      if (trackParams[i].toMap() == null) {
        continue;
      }
      if (trackParams[i].getString('kind') === 'audio') {
        audioTracks.pushMap(trackParams[i].toMap());
      } else {
        videoTracks.pushMap(trackParams[i].toMap());
      }
    }

    let streamId: string = mediaStream.id;
    Log.d(TAG, 'MediaStream id: ' + streamId);
    this.stateProvider?.putLocalStream(streamId, mediaStream);

    successResult.putString('streamId', streamId);
    successResult.putArray('audioTracks', audioTracks.toArrayList());
    successResult.putArray('videoTracks', videoTracks.toArrayList());
    result.success(successResult.toMap());
  }

  getDisplayMedia(constraints: ConstraintsMap, result: MethodResult, mediaStream: MediaStream) {
    Log.d(TAG, 'getDisplayMedia in!');
  }

  getUserAudio(constraints: ConstraintsMap, stream: MediaStream): ConstraintsMap {
    Log.d(TAG, 'getUserAudio in!');
    Log.d(TAG, 'getUserAudio in!' + JSON.stringify(constraints));
    AudioSwitchManager.instance.start()
    let deviceId: string | null = null
    Log.d(TAG, 'getUserAudio audio getType  ' + constraints.getType('audio'));
    if (constraints.getType('audio') == ObjectType.Null) {

    } else {
      deviceId = this.getSourceIdConstraint(constraints.getMap('audio'));
    }

    let trackId: string = this.stateProvider!.getNextTrackUUID();
    let pcFactory: PeerConnectionFactory = this.stateProvider!.getPeerConnectionFactory();
    let audioSource: AudioSource = pcFactory.createAudioSource();

    if (deviceId != null) {
      try {
      } catch (e) {
        Log.d(TAG, 'setPreferredInputDevice error  ' + JSON.stringify(e));
      }
    }

    let track: AudioTrack = pcFactory.createAudioTrack('audio', audioSource);
    stream.addTrack(track);

    this.stateProvider!.putLocalTrack(track.id, track);

    let trackParams: ConstraintsMap = new ConstraintsMap();
    trackParams.putBoolean('enabled', track.enabled);
    trackParams.putString('id', track.id);
    trackParams.putString('kind', 'audio');
    trackParams.putString('label', track.id);
    trackParams.putString('readyState', track.readyState.toString());
    trackParams.putBoolean('remote', false);

    if (deviceId == null) {
      deviceId = '' + -1;
    }

    let settings: ConstraintsMap = new ConstraintsMap();
    settings.putString('deviceId', deviceId);
    settings.putString('kind', 'audioinput');
    settings.putBoolean('autoGainControl', true);
    settings.putBoolean('echoCancellation', true);
    settings.putBoolean('noiseSuppression', true);
    settings.putNumber('channelCount', 1);
    settings.putNumber('latency', 0);
    trackParams.putMap('settings', settings.toMap());

    Log.d(TAG, 'getUserAudio out!');
    return trackParams;
  }

  getUserVideo(constraints: ConstraintsMap, stream: MediaStream): ConstraintsMap {
    Log.d(TAG, 'getUserVideo in!');

    let videoConstraintsMap: ConstraintsMap = new ConstraintsMap();
    let videoConstraintsMandatory: ConstraintsMap = new ConstraintsMap();
    if (constraints.getType('video') == ObjectType.Map) {
      videoConstraintsMap = constraints.getMap('video')!;
      if (videoConstraintsMap.getType('mandatory') == ObjectType.Map) {
        videoConstraintsMandatory = videoConstraintsMap.getMap('mandatory')!;
      }
    }
    // Log.d(TAG, 'getUserVideo videoConstraintsMandatory:转换为数组并打印 = ' +  Array.from(videoConstraintsMandatory.toMap().entries()));

    let facingMode: string = this.getFacingMode(videoConstraintsMap);
    this.isFacing = facingMode === '' || !(facingMode === 'environment');
    Log.d(TAG, 'getUserVideo facingMode=' + facingMode + ' isFacing=' + this.isFacing);

    let deviceId: string = '';
    Log.d(TAG, 'getUserVideo deviceId=' + deviceId);

    let videoWidth: number | null = this.getConstrainNumber(videoConstraintsMap, 'width');
    videoWidth = videoWidth != null ?
      videoWidth :
      videoConstraintsMandatory != null ?
      videoConstraintsMandatory.getNumber('minWidth') :
      GetUserMediaImpl.DEFAULT_WIDTH;

    let videoHeight = this.getConstrainNumber(videoConstraintsMap, 'height');
    videoHeight = videoHeight != null ?
      videoHeight :
      videoConstraintsMandatory != null ?
      videoConstraintsMandatory.getNumber('minHeight') :
      GetUserMediaImpl.DEFAULT_HEIGHT;

    let videoFrameRate = this.getConstrainNumber(videoConstraintsMap, 'frameRate');
    videoFrameRate = videoFrameRate != null ?
      videoFrameRate :
      videoConstraintsMandatory != null ?
      videoConstraintsMandatory.getNumber('minFrameRate') :
      GetUserMediaImpl.DEFAULT_HEIGHT;

    let trackId: string = this.stateProvider!.getNextTrackUUID();
    let pcFactory: PeerConnectionFactory = this.stateProvider!.getPeerConnectionFactory();
    let videoSource: VideoSource = pcFactory.createVideoSource();

    let track: VideoTrack = pcFactory.createVideoTrack('video', videoSource);
    stream.addTrack(track);

    this.stateProvider!.putLocalTrack(track.id, track);
    let trackParams: ConstraintsMap = new ConstraintsMap();
    trackParams.putBoolean('enabled', track.enabled);
    trackParams.putString('id', track.id);
    trackParams.putString('kind', 'video');
    trackParams.putString('label', track.id);
    trackParams.putString('readyState', track.readyState.toString());
    trackParams.putBoolean('remote', false);

    if (deviceId == null) {
      deviceId = '' + -1;
    }

    let settings: ConstraintsMap = new ConstraintsMap();
    settings.putString('deviceId', deviceId);
    settings.putString('kind', 'videoinput');
    settings.putNumber('width', videoWidth!);
    settings.putNumber('height', videoHeight!);
    settings.putNumber('frameRate', videoFrameRate!);
    if (facingMode != null) {
      settings.putString('facingMode', facingMode);
    }
    trackParams.putMap('settings', settings.toMap());

    Log.d(TAG, 'getUserVideo trackParams:转换为数组并打印 = ' + Array.from(trackParams.toMap().entries()));
    Log.d(TAG, 'getUserVideo trackParams settings:转换为数组并打印 = ' + Array.from(settings.toMap().entries()));
    Log.d(TAG, 'getUserVideo out!');
    return trackParams;
  }

  /**
   * Retrieves 'facingMode' constraint value.
   *
   * @param mediaConstraints a <tt>ConstraintsMap</tt> which represents 'GUM' constraints argument.
   * @return String value of 'facingMode' constraints in 'GUM' or <tt>null</tt> if not specified.
   */
  private getFacingMode(mediaConstraints: ConstraintsMap): string {
    return mediaConstraints == null ? '' : mediaConstraints.getString('facingMode') as string;
  }

  /**
   * Retrieves 'sourceId' constraint value.
   *
   * @param mediaConstraints a <tt>ConstraintsMap</tt> which represents 'GUM' constraints argument
   * @return String value of 'sourceId' optional 'GUM' constraint or <tt>null</tt> if not specified.
   */
  private getSourceIdConstraint(mediaConstraints: ConstraintsMap | null): string {
    if (mediaConstraints && mediaConstraints.hasKey('deviceId')) {
      return mediaConstraints.getString('deviceId');
    }

    if (mediaConstraints && mediaConstraints.getType('optional') == ObjectType.Array) {
      let optional: ConstraintsArray = mediaConstraints.getArray('optional')!;
      for (let i = 0; i < optional.size(); i++) {
        if (optional.getType(i) == ObjectType.Map) {
          let option = new ConstraintsMap(optional.getMap(i));
          if (option.getType('sourceId') == ObjectType.String) {
            return option.getString('sourceId');
          }
        }
      }
    }

    return '';
  }

  /**
   * @return Returns the integer at the key, or the `ideal` property if it is a map.
   */
  private getConstrainNumber(constraintsMap: ConstraintsMap, key: string): number | null {
    if (constraintsMap == null) {
      return null;
    }

    if (constraintsMap.getType(key) == ObjectType.Number) {
      try {
        return constraintsMap.getNumber(key);
      } catch (e) {
        // Could be a double instead
        return Math.round(constraintsMap.getNumber(key));
      }
    }

    if (constraintsMap.getType(key) == ObjectType.String) {
      try {
        return parseInt(constraintsMap.getString(key) as string);
      } catch (e) {
        // Could be a double instead
        return Math.round(constraintsMap.getNumber(key));
      }
    }

    if (constraintsMap.getType(key) == ObjectType.Map) {
      let innerMap = constraintsMap.getMap(key)!;
      if (innerMap.getType('ideal') == ObjectType.Number) {
        return innerMap.getNumber('ideal');
      }
    }
    return null;
  }


  /**
   * check torchMode is available
   * */
  hasTorch(trackId: string, result: MethodResult): void {
    /*
     * 修改逻辑，通过trackID获取当前track
     * 通过track获取当前相机是哪个，
     * */
    Log.d(TAG, `hasTorch in`);

    let hasTorch = isTorchSupported();
    result.success(hasTorch ? hasTorch : false);
  }

  setTorch(torch: boolean, result: MethodResult): void {
    Log.d(TAG, `setTorch in`);
    try {
      setTorchMode(torch ? camera.FlashMode.FLASH_MODE_ALWAYS_OPEN : camera.FlashMode.FLASH_MODE_CLOSE);
      result.success(null);
      this.isTorchOn = torch;
    } catch (error) {
      // 失败返回错误码error.code并处理
      let err = error as BusinessError;
      Log.e(TAG, `The setTorchMode call failed. error code: ${err.code}`);
      this.resultError('setTorch', `The setTorchMode call failed. error code: ${err.code}`, result);
    }
  }

  private cameraPosition: boolean = false

  switchCamera(trackId: string, result: MethodResult): void {
    Log.d(TAG, `switchCamera in`);
    try {
      this.cameraPosition = !this.cameraPosition;
      switchCamera(Number(this.cameraPosition), this.surfaceTextureEntry!.getSurfaceId().toString(), 0);
      result.success(true);
    } catch (error) {
      // 失败返回错误码error.code并处理
      let err = error as BusinessError;
      Log.e(TAG, `The setTorchMode call failed. error code: ${err.code}`);
      this.resultError('switchCamera', `The switchCamera call failed. error code: ${err.code}`, result);
    }
  }

  setZoom(trackId: string, zoomLevel: number, result: MethodResult): void {
    Log.d(TAG, `setZoom in`);
    try {
      setZoom(zoomLevel);
      result.success(null);
    } catch (error) {
      // 失败返回错误码error.code并处理
      let err = error as BusinessError;
      Log.e(TAG, `The setTorchMode call failed. error code: ${err.code}`);
      this.resultError('switchCamera', `The switchCamera call failed. error code: ${err.code}`, result);
    }
  }

  removeVideoCapturer(id: string): void {

  }
}


