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

import { TextureRegistry, SurfaceTextureEntry, Log } from '@ohos/flutter_ohos';
import { MediaStream, NativeVideoRenderer, MediaStreamTrack } from 'libohos_webrtc.so';
import {
  beginConfig,
  getCameraDevices,
  getCameraInput,
  getCameraManager,
  getCaptureSession,
  getPreviewOutput,
  getSupportedOutputCapability,
  setSessionCameraInput,
  setSessionPreviewOutput,
  startSession,
  stopSession,
  releaseCamera,
  isTorchSupported,
  setTorchMode,
  switchCamera
} from './utils/CameraUtil';
import { common } from '@kit.AbilityKit';
import StateProvider from './StateProvider';

const TAG: string = 'FlutterWebRTCPlugin-SurfaceTextureRenderer';

export default class SurfaceTextureRenderer extends NativeVideoRenderer {
  private textures: TextureRegistry | null = null
  private id: number = -1
  private mediaStream: MediaStream | null = null
  private ownerTag: string = ''
  private stateProvider: StateProvider | null = null;
  private surfaceTextureEntry: SurfaceTextureEntry | null = null
  private renderer: NativeVideoRenderer | null = null;

  constructor(name?: string) {
    super();
  }

  setStateProvider(stateProvider: StateProvider) {
    this.stateProvider = stateProvider;
  }

  surfaceCreated(entry: SurfaceTextureEntry) {
    this.surfaceTextureEntry = entry;
    let surfaceId = this.surfaceTextureEntry!.getSurfaceId().toString();
    Log.d(TAG, 'surfaceCreated surfaceId: ' + surfaceId);
  }

  setVideoTrack(track: MediaStreamTrack | null): void {
    Log.d(TAG, 'setVideoTrack track.id: ' + track?.id);
    this.renderer?.setVideoTrack(track);
  }

  startRender() {
    this.startSession();
  }

  stopRender() {
    this.stopSession();
    this.renderer?.release();
  }

  private startSession() {
    Log.d(TAG, `startSession`);
    getCameraManager(getContext() as common.BaseContext);
    switchCamera(0, this.surfaceTextureEntry!.getSurfaceId().toString(), 0);
  }

  private stopSession() {
    Log.d(TAG, `stopSession`);
    releaseCamera();
  }
}