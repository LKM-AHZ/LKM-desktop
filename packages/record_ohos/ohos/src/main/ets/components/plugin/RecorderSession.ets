/* Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND. See the License for the specific language governing
 * permissions and limitations under the License.
 */
import { BinaryMessenger, MethodCall } from '@ohos/flutter_ohos';
import EventChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import fs from '@ohos.file.fs';
import { BusinessError } from '@kit.BasicServicesKit';
import { StateEvents, DataEvents } from './RecordEvents';

export class RecorderSession {
  readonly states: StateEvents = new StateEvents();
  readonly data: DataEvents = new DataEvents();
  private stateChannel: EventChannel;
  private dataChannel: EventChannel;
  private av: media.AVRecorder | null = null;
  private pcm: audio.AudioCapturer | null = null;
  private file: fs.File | null = null;
  private path: string | null = null;
  private recoveredPath: string | null = null;
  private streaming: boolean = false;
  private accepting: boolean = false;
  private stopping: boolean = false;
  private wav: boolean = false;
  private byteCount: number = 0;
  private sampleRate: number = 44100;
  private channels: number = 2;
  private currentDb: number = -160;
  private maxDb: number = -160;
  private failed: boolean = false;
  private fail: (session: RecorderSession, message: string) => void;

  constructor(id: string, messenger: BinaryMessenger,
    fail: (session: RecorderSession, message: string) => void) {
    this.fail = fail;
    this.stateChannel = new EventChannel(messenger, 'com.llfbandit.record/events/' + id);
    this.dataChannel = new EventChannel(messenger, 'com.llfbandit.record/eventsRecord/' + id);
    this.stateChannel.setStreamHandler(this.states);
    this.dataChannel.setStreamHandler(this.data);
  }

  static supported(encoder: string): boolean { return ['aacLc', 'pcm16bits', 'wav'].includes(encoder); }

  async start(call: MethodCall, stream: boolean): Promise<void> {
    if (this.av !== null || this.pcm !== null) throw new Error('Recorder is already active');
    const encoder = call.argument('encoder') as string;
    if (!RecorderSession.supported(encoder) || (stream && encoder !== 'pcm16bits')) {
      throw new Error('Unsupported encoder: ' + encoder + (stream ? ' for stream recording' : ''));
    }
    if (call.argument('device') != null) throw new Error('Explicit input device selection is not supported');
    this.sampleRate = call.argument('sampleRate') as number;
    this.channels = call.argument('numChannels') as number;
    const bitRate = call.argument('bitRate') as number;
    if (!Number.isInteger(this.sampleRate) || this.sampleRate <= 0 ||
      ![1, 2].includes(this.channels) || !Number.isInteger(bitRate) || bitRate <= 0) {
      throw new Error('Invalid recording configuration');
    }
    const path = stream ? null : call.argument('path') as string;
    if (!stream && (path == null || !path.startsWith('/') || path.includes('\u0000'))) {
      throw new Error('Recording requires an absolute writable file path');
    }
    this.streaming = stream; this.wav = encoder === 'wav'; this.byteCount = 0;
    this.recoveredPath = null;
    this.currentDb = -160; this.maxDb = -160; this.failed = false;
    this.data.reset();
    try {
      if (encoder === 'aacLc') {
        this.av = await media.createAVRecorder();
        this.av.on('error', (error: BusinessError) => this.reportError(error.message));
        this.av.on('stateChange', (state: media.AVRecorderState) => {
          if (state === 'stopped' && this.accepting && !this.stopping) this.reportError('System stopped audio recording');
        });
        this.file = fs.openSync(path!, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        this.path = path;
        await this.av.prepare({
          audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
          profile: { audioCodec: media.CodecMimeType.AUDIO_AAC,
            fileFormat: media.ContainerFormatType.CFT_MPEG_4A,
            audioBitrate: bitRate, audioSampleRate: this.sampleRate, audioChannels: this.channels },
          url: 'fd://' + this.file.fd,
        });
        await this.av.start();
        this.accepting = true;
      } else {
        this.pcm = await audio.createAudioCapturer({
          streamInfo: { samplingRate: this.sampleRate, channels: this.channels,
            sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
            encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
          capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 },
        });
        const actual = await this.pcm.getStreamInfo();
        if (actual.samplingRate !== this.sampleRate || actual.channels !== this.channels ||
          actual.sampleFormat !== audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE) {
          throw new Error('Requested PCM format is not supported by this device');
        }
        if (!stream) {
          this.file = fs.openSync(path!, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          this.path = path;
          if (this.wav) this.write(this.wavHeader(), 0);
        }
        this.pcm.on('readData', (buffer: ArrayBuffer) => this.read(buffer));
        this.pcm.on('stateChange', (state: audio.AudioState) => {
          if (this.accepting && !this.stopping && [audio.AudioState.STATE_STOPPED,
            audio.AudioState.STATE_RELEASED, audio.AudioState.STATE_PAUSED].includes(state)) {
            this.reportError('System stopped PCM recording');
          }
        });
        this.pcm.on('audioInterrupt', (event: audio.InterruptEvent) => {
          if (event.forceType === audio.InterruptForceType.INTERRUPT_FORCE && this.accepting &&
            [audio.InterruptHint.INTERRUPT_HINT_STOP, audio.InterruptHint.INTERRUPT_HINT_PAUSE].includes(event.hintType)) {
            this.reportError('System interrupted audio recording');
          }
        });
        this.accepting = true;
        await this.pcm.start();
      }
      if (this.failed) throw new Error('Recording failed during start');
      this.states.send(1);
    } catch (error) {
      try { await this.finish(true); } catch (cleanupError) { console.error('Failed recording cleanup'); }
      throw error as Error;
    }
  }

  private reportError(message: string): void {
    if (this.failed) return;
    this.failed = true; this.accepting = false;
    this.states.error(message);
    if (this.streaming) this.data.error(message);
    this.fail(this, message);
  }

  private read(buffer: ArrayBuffer): void {
    if (!this.accepting) return;
    try {
      if (buffer.byteLength % (2 * this.channels) !== 0) throw new Error('Incomplete PCM frame');
      const samples = new DataView(buffer);
      let peak = 0;
      for (let i = 0; i < buffer.byteLength; i += 2) peak = Math.max(peak, Math.abs(samples.getInt16(i, true)));
      this.setAmplitude(peak);
      if (this.streaming) this.data.send(new Uint8Array(buffer.slice(0)));
      else {
        if (this.byteCount + buffer.byteLength > 0xffffffff - 36) throw new Error('Recording exceeds WAV/PCM file limit');
        this.write(buffer, this.byteCount + (this.wav ? 44 : 0));
      }
      this.byteCount += buffer.byteLength;
    } catch (error) { this.reportError((error as Error).message); }
  }

  private write(buffer: ArrayBuffer, offset: number): void {
    fs.lseek(this.file!.fd, offset, fs.WhenceType.SEEK_SET);
    let done = 0;
    while (done < buffer.byteLength) {
      const length = fs.writeSync(this.file!.fd, buffer.slice(done));
      if (length <= 0 || length > buffer.byteLength - done) throw new Error('Recording file write made no progress');
      done += length;
    }
  }

  private wavHeader(): ArrayBuffer {
    const buffer = new ArrayBuffer(44);
    const view = new DataView(buffer);
    const tag = (offset: number, value: string): void => {
      for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i));
    };
    tag(0, 'RIFF'); view.setUint32(4, 36 + this.byteCount, true); tag(8, 'WAVE');
    tag(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
    view.setUint16(22, this.channels, true); view.setUint32(24, this.sampleRate, true);
    view.setUint32(28, this.sampleRate * this.channels * 2, true);
    view.setUint16(32, this.channels * 2, true); view.setUint16(34, 16, true);
    tag(36, 'data'); view.setUint32(40, this.byteCount, true);
    return buffer;
  }

  async pause(): Promise<void> {
    if (this.states.state !== 1) return;
    if (this.av !== null) await this.av.pause();
    if (this.pcm !== null) {
      this.stopping = true;
      try { await this.pcm.stop(); this.accepting = false; }
      finally { this.stopping = false; }
    }
    this.states.send(0);
  }
  async resume(): Promise<void> {
    if (this.states.state !== 0) return;
    if (this.av !== null) await this.av.resume();
    if (this.pcm !== null) { this.accepting = true; await this.pcm.start(); }
    this.states.send(1);
  }
  private setAmplitude(peak: number): void {
    this.currentDb = peak > 0 ? Math.max(-160, Math.min(0, 20 * Math.log10(peak / 32768))) : -160;
    this.maxDb = Math.max(this.maxDb, this.currentDb);
  }
  async amplitude(): Promise<Map<string, number>> {
    if (this.av !== null && this.states.state === 1) this.setAmplitude(await this.av.getAudioCapturerMaxAmplitude());
    return new Map<string, number>([['current', this.states.state === 1 ? this.currentDb : -160], ['max', this.maxDb]]);
  }

  async finish(discard: boolean): Promise<string | null> {
    this.stopping = true;
    const av = this.av; this.av = null;
    const pcm = this.pcm; this.pcm = null;
    const path = this.path ?? this.recoveredPath; this.path = null; this.recoveredPath = null;
    let failure: Error | null = null;
    try {
      if (av !== null) {
        try { if (av.state === 'started' || av.state === 'paused') await av.stop(); }
        finally { await av.release(); }
      }
      if (pcm !== null) {
        try { if (pcm.state === audio.AudioState.STATE_RUNNING) await pcm.stop(); }
        finally {
          try { pcm.off('readData'); pcm.off('audioInterrupt'); pcm.off('stateChange'); }
          finally { await pcm.release(); }
        }
      }
      if (this.wav && this.file !== null && !discard) this.write(this.wavHeader(), 0);
    } catch (error) { failure = error as Error; }
    finally {
      this.accepting = false; this.stopping = false;
      const file = this.file; this.file = null;
      try { if (file !== null) fs.closeSync(file); }
      catch (error) { failure = error as Error; }
      this.states.send(2);
      if (this.streaming) this.data.end();
      this.streaming = false;
    }
    if (discard && path !== null) fs.unlinkSync(path);
    if (failure !== null) throw failure;
    return path;
  }

  async recover(): Promise<void> { this.recoveredPath = await this.finish(false); }

  async dispose(): Promise<void> {
    try { await this.finish(true); }
    finally { this.stateChannel.setStreamHandler(null); this.dataChannel.setStreamHandler(null); }
  }
}
