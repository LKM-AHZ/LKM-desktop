// Copyright 2026 The LKM Authors. MIT license; see LICENSE.
import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';
import { MediaStreamTrack, NativeVideoRenderer } from 'libohos_webrtc.so';

// This renderer owns only its encoder surface, never the caller's shared track.
export class TrackRecorder {
  private recorder?: media.AVRecorder;
  private renderer?: NativeVideoRenderer;
  private file?: fs.File;
  private starting?: Promise<void>;

  start(path: string, track: MediaStreamTrack, width: number, height: number): Promise<void> {
    if (this.starting) return Promise.reject(new Error('Recorder already started'));
    this.starting = this.prepare(path, track, width, height);
    return this.starting;
  }

  private async prepare(path: string, track: MediaStreamTrack, width: number, height: number): Promise<void> {
    if (!path.endsWith('.mp4')) throw new Error('OHOS video recording requires an .mp4 path');
    try {
      // Do not silently destroy an existing recording on startup failure.
      if (fs.accessSync(path)) throw new Error('Recording path already exists');
      this.file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      this.recorder = await media.createAVRecorder();
      await this.recorder.prepare({
        videoSourceType: media.VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_YUV,
        profile: {
          fileFormat: media.ContainerFormatType.CFT_MPEG_4,
          videoCodec: media.CodecMimeType.VIDEO_AVC,
          videoBitrate: 2000000, videoFrameRate: 30,
          videoFrameWidth: width, videoFrameHeight: height
        },
        url: `fd://${this.file.fd}`
      });
      const surface = await this.recorder.getInputSurface();
      this.renderer = new NativeVideoRenderer();
      this.renderer.init(surface);
      await this.recorder.start();
      this.renderer.setVideoTrack(track);
    } catch (error) {
      await this.release();
      throw error as Error;
    }
  }

  async stop(): Promise<void> {
    try {
      await this.starting;
      this.renderer?.setVideoTrack(null);
      await this.recorder?.stop();
    } finally { await this.release(); }
  }

  async release(): Promise<void> {
    try {
      this.renderer?.setVideoTrack(null);
      this.renderer?.release();
    } finally {
      this.renderer = undefined;
      try { await this.recorder?.release(); }
      finally {
        this.recorder = undefined;
        if (this.file) fs.closeSync(this.file);
        this.file = undefined;
      }
    }
  }
}
