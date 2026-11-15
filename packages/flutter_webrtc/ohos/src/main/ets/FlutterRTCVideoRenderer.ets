/* MIT License
*
* Copyright (c) 2024 SwanLink (Jiangsu) Technology Development Co., LTD.
* All rights reserved.
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the 'Software'), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import { MethodResult, EventChannel, Log } from '@ohos/flutter_ohos';
import { TextureRegistry } from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { ConstraintsMap } from './utils/ConstraintsMap';
import webrtc, { MediaStream, MediaStreamTrack, NativeVideoRenderer, VideoTrack } from 'libohos_webrtc.so';
import StateProvider from './StateProvider';

const TAG: string = 'FlutterWebRTCPlugin-FlutterRTCVideoRenderer';

export default class FlutterRTCVideoRenderer implements StreamHandler {
  private id: number = -1
  private surfaceId: string = ''
  private mediaStream: MediaStream | null = null
  private ownerTag: string | null = ''
  private videoTrack: VideoTrack | null = null;
  eventChannel: EventChannel | null = null;
  eventSink: EventSink | null = null;
  _width: number = 0;
  _height: number = 0;
  _rotation: number = -1;
  private nativeVideoRenderer: NativeVideoRenderer

  private registry: TextureRegistry;
  constructor(textureId: number, stateProvider: StateProvider, registry: TextureRegistry) {
    this.registry = registry;
    this.id = textureId;
    this.nativeVideoRenderer = new NativeVideoRenderer();
    this.nativeVideoRenderer.onFrameResolutionChanged = (data: ESObject) => this.frameResolutionChanged(data)
    this.eventSink = null;
    this.ownerTag = '';
  }

  frameResolutionChanged(data: ESObject): void {
    if (data.width <= 0 || data.height <= 0) return;
    this._width = data.width; this._height = data.height; this._rotation = data.rotation;
    this.registry.notifyTextureResizing(this.id, this._width, this._height);
    this.publishSize();
  }
  private publishSize(): void {
    if (this.eventSink === null || this._width <= 0 || this._height <= 0) return;
    const size = new ConstraintsMap();
    size.putString('event', 'didTextureChangeVideoSize'); size.putNumber('id', this.id);
    size.putNumber('width', this._width); size.putNumber('height', this._height);
    this.eventSink.success(size.toMap());
    const rotation = new ConstraintsMap();
    rotation.putString('event', 'didTextureChangeRotation'); rotation.putNumber('id', this.id);
    rotation.putNumber('rotation', this._rotation); this.eventSink.success(rotation.toMap());
  }

  setId(id: number) {
    this.id = id;
  }

  getId(): number { return this.id; }

  hasVideoTrack(trackId: string): boolean { return this.videoTrack?.id === trackId; }

  getSurfaceId(): string {
    return this.surfaceId
  }

  init(id: string) {
    if (this.surfaceId == '') {
      //首次进入
      this.surfaceId = id
      this.nativeVideoRenderer.init(this.surfaceId)
    } else {
      //被替换,释放重新创建
      Log.d(TAG, 'init surfaceId :  ' + id);
      this.nativeVideoRenderer.release()
      this.nativeVideoRenderer = new NativeVideoRenderer();
      this.nativeVideoRenderer.onFrameResolutionChanged = (data: ESObject) => this.frameResolutionChanged(data);
      this.surfaceId = id
      this.nativeVideoRenderer.init(this.surfaceId)
      this.nativeVideoRenderer.setVideoTrack(this.videoTrack);
    }
  }

  onListen(args: ESObject, events: EventSink): void {
    this.eventSink = events;
    this.publishSize();
  }

  onCancel(args: ESObject): void {
    this.eventSink = null;
  }

  public setEventChannel(eventChannel: EventChannel): void {
    this.eventChannel = eventChannel;
  }

  resultError(method: string, error: string, result: MethodResult) {
    let errorMsg: string = method + '(): ' + error;
    result.error(method, errorMsg, null);
    Log.d(TAG, errorMsg);
  }

  public Dispose(): void {
    if (this.eventChannel != null) {
      this.eventChannel?.setStreamHandler(null);
    }
    this.eventSink = null;
    this.nativeVideoRenderer.setVideoTrack(null);
    this.videoTrack = null;
    this.nativeVideoRenderer.release()
  }

  public setStream(mediaStream: MediaStream | null, ownerTag: string | null, trackId?: string): void {
    let videoTrack: MediaStreamTrack | null
    this.mediaStream = mediaStream;
    this.ownerTag = ownerTag;
    Log.d(TAG, 'mediaStream id :' + this.mediaStream?.id);
    Log.d(TAG, 'mediaStream surfaceId :' + this.surfaceId);
    Log.d(TAG, 'mediaStream trackId :' + trackId);
    Log.d(TAG, 'mediaStream ownerTag :' + ownerTag);
    if (mediaStream == null) {
      Log.d(TAG, 'mediaStream mediaStream null :');
      videoTrack = null
    } else {
      let videoTracks: MediaStreamTrack[] = mediaStream?.getVideoTracks()
      videoTrack = (trackId == null || trackId === '0') ? (videoTracks[0] ?? null) : (videoTracks.find((track: MediaStreamTrack): boolean => track.id === trackId) ?? null)
    }
    Log.e(TAG, 'setStream  setVideoTrack : ' + videoTrack?.id);
    this.setVideoTrack(videoTrack);
  }

  setVideoTrack(videoTrack: MediaStreamTrack | null) {
    let oldValue: MediaStreamTrack | null = this.videoTrack;
    Log.d(TAG, 'setStream  setVideoTrack oldValue : ' + oldValue?.id);
    Log.d(TAG, 'setStream  setVideoTrack videoTrack : ' + videoTrack?.id);
    if (oldValue?.id == videoTrack?.id) {
      Log.w(TAG, 'FlutterRTCVideoRenderer VideoTrack no change');
      return;
    }
    if (oldValue) {
      this.removeRendererFromVideoTrack();
    }
    this._width = 0; this._height = 0; this._rotation = -1;
    this.videoTrack = videoTrack;
    if (!videoTrack) {
      Log.e(TAG, 'FlutterRTCVideoRenderer.setVideoTrack, set video track to null');
      return;
    }
    try {
      Log.d(TAG, 'FlutterRTCVideoRenderer.setVideoTrack, set video track to ' + videoTrack.id);
      this.tryAddRendererToVideoTrack();
    } catch (e) {
      Log.e(TAG, 'tryAddRendererToVideoTrack ' + e);
    }
  }

  removeRendererFromVideoTrack() {
    this.nativeVideoRenderer.setVideoTrack(null);
  }

  tryAddRendererToVideoTrack() {
    if (this.videoTrack) {
      this.nativeVideoRenderer.setVideoTrack(this.videoTrack)
    }
  }

  public checkMediaStream(id: string, ownerTag: string): boolean {
    if (null == id || null == this.mediaStream || ownerTag == null || ownerTag !== this.ownerTag) {
      return false;
    }
    return id === this.mediaStream.id;
  }

  public checkVideoTrack(id: string, ownerTag: string): boolean {
    if (null == id || null == this.videoTrack || ownerTag == null || ownerTag !== this.ownerTag) {
      return false;
    }
    return id === this.videoTrack.id;
  }
}
