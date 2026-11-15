import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadArkTs } from './ohos-test-loader.mjs';

// Run actual ArkTS state/resource logic against real temporary files, mocking only SDK boundaries.
const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'lkm-ohos-record-'));
const channels = new Map();
class EventChannel {
  constructor(_, name) { channels.set(name, this); }
  setStreamHandler(handler) { this.handler = handler; }
}
class MethodChannel {
  constructor(_, name) { channels.set(name, this); }
  setMethodCallHandler(handler) { this.handler = handler; }
}
const flutter = { MethodChannel };
const eventPath = '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
const events = loadArkTs(new URL('../packages/record_ohos/ohos/src/main/ets/components/plugin/RecordEvents.ets', import.meta.url),
  new Map([['@ohos/flutter_ohos', flutter], [eventPath, {}]]));
const openFiles = new Map();
let partialWrites = false;
let zeroWrite = false;
const nativeFs = {
  OpenMode: { READ_WRITE: 2, CREATE: 64, TRUNC: 512 }, WhenceType: { SEEK_SET: 0 },
  openSync(name, flags) {
    const fd = fs.openSync(name, flags);
    openFiles.set(fd, 0);
    return { fd };
  },
  closeSync(file) { assert(openFiles.has(file.fd), 'FD closed exactly once'); fs.closeSync(file.fd); openFiles.delete(file.fd); },
  unlinkSync: name => fs.unlinkSync(name),
  lseek(fd, offset) { assert(openFiles.has(fd)); openFiles.set(fd, offset); return offset; },
  writeSync(fd, buffer) {
    if (zeroWrite) return 0;
    const bytes = Buffer.from(new Uint8Array(buffer));
    const size = fs.writeSync(fd, bytes, 0, partialWrites ? Math.min(3, bytes.length) : bytes.length, openFiles.get(fd));
    openFiles.set(fd, openFiles.get(fd) + size); return size;
  },
};
let startGate;
let prepareFailure = false;
let capturer;
let av;
let avCount = 0;
let capturerCount = 0;
let tailOnStop = false;
const audio = {
  AudioSampleFormat: { SAMPLE_FORMAT_S16LE: 1 }, AudioEncodingType: { ENCODING_TYPE_RAW: 0 },
  SourceType: { SOURCE_TYPE_MIC: 0 }, AudioState: { STATE_RUNNING: 2, STATE_STOPPED: 3, STATE_RELEASED: 4, STATE_PAUSED: 5 },
  InterruptForceType: { INTERRUPT_FORCE: 0 }, InterruptHint: { INTERRUPT_HINT_STOP: 3, INTERRUPT_HINT_PAUSE: 2 },
  async createAudioCapturer(options) {
    capturerCount++;
    capturer = {
      options, listeners: new Map(), state: 1, released: false,
      getStreamInfo: async () => options.streamInfo,
      on(name, fn) { this.listeners.set(name, fn); },
      off(name) { this.listeners.delete(name); },
      async start() { if (startGate) await startGate; this.state = 2; },
      async stop() {
        if (tailOnStop) this.listeners.get('readData')?.(new Uint8Array([1, 2, 3, 4]).buffer);
        this.state = 3;
        this.listeners.get('stateChange')?.(3);
      },
      async release() { assert(!this.released); this.released = true; },
    };
    return capturer;
  },
};
const media = {
  AudioSourceType: { AUDIO_SOURCE_TYPE_MIC: 1 }, CodecMimeType: { AUDIO_AAC: 'audio/mp4a-latm' },
  ContainerFormatType: { CFT_MPEG_4A: 'm4a' },
  async createAVRecorder() {
    avCount++;
    av = {
      state: 'idle', listeners: new Map(), released: false,
      on(name, fn) { this.listeners.set(name, fn); },
      async prepare(config) { this.config = config; if (prepareFailure) throw Error('prepare rejected'); this.state = 'prepared'; },
      async start() { if (startGate) await startGate; this.state = 'started'; },
      async pause() { this.state = 'paused'; }, async resume() { this.state = 'started'; },
      async stop() { this.state = 'stopped'; this.listeners.get('stateChange')?.('stopped'); },
      async release() { assert(!this.released); this.released = true; },
      async getAudioCapturerMaxAmplitude() { return 16384; },
    };
    return av;
  },
};
const sessionModule = loadArkTs(new URL('../packages/record_ohos/ohos/src/main/ets/components/plugin/RecorderSession.ets', import.meta.url),
  new Map([['@ohos/flutter_ohos', flutter], [eventPath, EventChannel],
    ['@kit.AudioKit', { audio }], ['@kit.MediaKit', { media }], ['@ohos.file.fs', nativeFs],
    ['./RecordEvents', events]]));
const { RecorderSession } = sessionModule;
const call = (method, args = {}) => ({ method, argument: key => args[key] ?? null });
const config = (encoder = 'aacLc', name = 'voice.m4a') => ({
  encoder, path: path.join(folder, name), bitRate: 128000, sampleRate: 44100, numChannels: 2,
});
const failures = [];
const session = new RecorderSession('test', {}, (_, message) => failures.push(message));
const pcmBytes = () => {
  const bytes = new ArrayBuffer(8); const view = new DataView(bytes);
  [0, 16384, -32768, 100].forEach((v, i) => view.setInt16(i * 2, v, true)); return bytes;
};
try {
  for (const encoder of ['opus', 'flac', 'aacEld', 'aacHe']) assert.equal(RecorderSession.supported(encoder), false);
  await assert.rejects(session.start(call('start', config('opus')), false), /Unsupported encoder/);
  assert.equal(avCount + capturerCount, 0, 'reject formats before creating/truncating resources');
  await assert.rejects(session.start(call('start', { ...config(), device: { id: '4' } }), false), /device selection/);

  let releaseStart;
  startGate = new Promise(resolve => { releaseStart = resolve; });
  let started = false;
  const starting = session.start(call('start', config()), false).then(() => { started = true; });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(started, false, 'start must wait for native capture');
  releaseStart(); await starting; startGate = null;
  assert.equal(session.states.state, 1);
  assert.equal(av.config.profile.audioCodec, 'audio/mp4a-latm');
  let amplitude = await session.amplitude();
  assert(Math.abs(amplitude.get('current') - (-6.020599913)) < 1e-6, 'linear samples become dBFS');
  await session.pause(); assert.equal(session.states.state, 0);
  await session.resume(); assert.equal(session.states.state, 1);
  assert.equal(await session.finish(false), config().path);
  await session.finish(true);
  assert(fs.existsSync(config().path), 'cancel after stop must not erase a completed recording');
  assert(av.released); assert.equal(openFiles.size, 0);

  prepareFailure = true;
  await assert.rejects(session.start(call('start', config('aacLc', 'failed.m4a')), false), /prepare rejected/);
  assert(!fs.existsSync(config('aacLc', 'failed.m4a').path));
  assert(av.released); assert.equal(openFiles.size, 0); prepareFailure = false;
  const missing = path.join(folder, 'absent', 'recording.wav');
  await assert.rejects(session.start(call('start', { ...config('wav'), path: missing }), false), /ENOENT/);
  assert(capturer.released); assert.equal(openFiles.size, 0);

  partialWrites = true;
  await session.start(call('start', config('wav', 'sample.wav')), false);
  capturer.listeners.get('readData')(pcmBytes());
  await session.pause(); capturer.listeners.get('readData')(pcmBytes());
  await session.resume(); capturer.listeners.get('readData')(pcmBytes());
  const wavPath = await session.finish(false);
  const wav = fs.readFileSync(wavPath);
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF'); assert.equal(wav.toString('ascii', 8, 12), 'WAVE');
  assert.equal(wav.readUInt32LE(4), 52); assert.equal(wav.readUInt32LE(40), 16);
  assert.equal(wav.readUInt16LE(22), 2); assert.equal(wav.readUInt32LE(24), 44100);
  assert.equal(wav.readUInt32LE(28), 176400); assert.equal(wav.readUInt16LE(34), 16);
  assert.deepEqual(wav.subarray(44), Buffer.concat([Buffer.from(pcmBytes()), Buffer.from(pcmBytes())]));
  assert(capturer.released); assert.equal(capturer.listeners.size, 0); assert.equal(openFiles.size, 0);

  await session.start(call('start', config('pcm16bits', 'raw.pcm')), false);
  capturer.listeners.get('readData')(pcmBytes());
  const raw = await session.finish(false);
  assert.deepEqual(fs.readFileSync(raw), Buffer.from(pcmBytes()));
  await session.start(call('start', config('pcm16bits', 'cancel.pcm')), false);
  await session.finish(true); assert(!fs.existsSync(config('pcm16bits', 'cancel.pcm').path));

  await assert.rejects(session.start(call('startStream', config()), true), /for stream/);
  await session.start(call('startStream', config('pcm16bits')), true);
  capturer.listeners.get('readData')(pcmBytes()); // First buffer arrives before Dart subscribes.
  const chunks = []; let ended = false;
  session.data.onListen(null, { success: bytes => chunks.push(Buffer.from(bytes)), endOfStream: () => { ended = true; } });
  capturer.listeners.get('readData')(pcmBytes());
  assert.equal(chunks.length, 2); assert.deepEqual(chunks[0], Buffer.from(pcmBytes()));
  tailOnStop = true;
  assert.equal(await session.finish(false), null); assert(ended);
  tailOnStop = false;
  assert.equal(chunks.length, 3, 'the final native buffer is delivered before end-of-stream');
  assert.deepEqual(chunks[2], Buffer.from([1, 2, 3, 4]));
  amplitude = await session.amplitude(); assert.equal(amplitude.get('current'), -160);

  await session.start(call('start', config('wav', 'full.wav')), false);
  zeroWrite = true;
  capturer.listeners.get('readData')(pcmBytes()); zeroWrite = false;
  assert.match(failures.at(-1), /no progress/);
  await session.recover(); assert.equal(await session.finish(false), config('wav', 'full.wav').path);
  assert.equal(openFiles.size, 0);
  await session.start(call('startStream', config('pcm16bits')), true);
  session.data.onCancel(null);
  const big = new ArrayBuffer(1048580);
  capturer.listeners.get('readData')(big);
  assert.match(failures.at(-1), /no consumer/);
  await session.finish(true);
  await session.dispose();

  let granted = false; let permissionRequests = 0; let permissionFailure = false;
  const manager = {
    checkAccessTokenSync: () => granted ? 0 : -1,
    async requestPermissionsFromUser() { permissionRequests++; if (permissionFailure) throw Error('permission SDK failed'); return { authResults: [granted ? 0 : -1] }; },
  };
  const Plugin = loadArkTs(new URL('../packages/record_ohos/ohos/src/main/ets/components/plugin/RecordOhosPlugin.ets', import.meta.url),
    new Map([['@ohos/flutter_ohos', flutter], ['./RecorderSession', sessionModule],
      ['@ohos.abilityAccessCtrl', { createAtManager: () => manager, GrantStatus: { PERMISSION_GRANTED: 0 } }],
      ['@ohos.bundle.bundleManager', { BundleFlag: { GET_BUNDLE_INFO_WITH_APPLICATION: 1 },
        getBundleInfoForSelfSync: () => ({ appInfo: { accessTokenId: 1 } }) }],
    ])).default;
  const plugin = new Plugin();
  plugin.onAttachedToEngine({ getBinaryMessenger: () => ({}) });
  plugin.onAttachedToAbility({ getAbility: () => ({ context: {} }) });
  const invoke = (method, args = {}) => new Promise(resolve => {
    plugin.onMethodCall(call(method, { recorderId: 'public', ...args }), {
      success: value => resolve({ value }), error: (code, message) => resolve({ code, message }),
    });
  });
  assert.equal((await invoke('create')).value, null);
  assert.equal((await invoke('hasPermission', { request: false })).value, false);
  assert.equal(permissionRequests, 0, 'check-only must never prompt');
  assert.equal((await invoke('hasPermission', { request: true })).value, false);
  assert.equal(permissionRequests, 1);
  permissionFailure = true;
  assert.match((await invoke('hasPermission')).message, /permission SDK failed/); permissionFailure = false;
  assert.match((await invoke('start', config())).message, /permission denied/);
  assert.equal((await invoke('isRecording')).value, false);
  granted = true;
  assert.equal((await invoke('hasPermission', { request: false })).value, true);
  assert.equal((await invoke('isEncoderSupported', { encoder: 'flac' })).value, false);
  assert.equal((await invoke('start', config('wav', 'public.wav'))).value, null);
  assert.equal((await invoke('isRecording')).value, true);
  await invoke('cancel'); assert.equal(openFiles.size, 0);
  assert(!fs.existsSync(config('wav', 'public.wav').path));
  // An asynchronous SDK error finalizes the prefix and preserves its path for stop.
  await invoke('start', config('wav', 'interrupted.wav'));
  capturer.listeners.get('readData')(pcmBytes());
  capturer.listeners.get('audioInterrupt')({ forceType: 0, hintType: 3 });
  await plugin.queue;
  assert.equal((await invoke('stop')).value, config('wav', 'interrupted.wav').path);
  assert.equal(openFiles.size, 0);
  await invoke('start', config('wav', 'system-stop.wav'));
  capturer.state = 3;
  capturer.listeners.get('stateChange')(3);
  await plugin.queue;
  assert.equal((await invoke('isRecording')).value, false);
  assert.equal((await invoke('stop')).value, config('wav', 'system-stop.wav').path);
  await invoke('start', config('aacLc', 'detach.m4a'));
  plugin.onDetachedFromAbility();
  await plugin.queue;
  assert.equal(openFiles.size, 0); assert(av.released);
  assert(!fs.existsSync(config('aacLc', 'detach.m4a').path));
  plugin.onAttachedToAbility({ getAbility: () => ({ context: {} }) });
  await invoke('create');
  let releasePendingStart;
  startGate = new Promise(resolve => { releasePendingStart = resolve; });
  const pendingStart = invoke('start', config('aacLc', 'pending-detach.m4a'));
  await new Promise(resolve => setImmediate(resolve));
  plugin.onDetachedFromAbility();
  releasePendingStart();
  assert.match((await pendingStart).message, /ability detached/);
  await plugin.queue; startGate = null;
  assert.equal(openFiles.size, 0);
  assert(!fs.existsSync(config('aacLc', 'pending-detach.m4a').path));
  plugin.onDetachedFromEngine({}); await plugin.queue;
  assert.equal(channels.get('com.llfbandit.record/messages').handler, null);
  assert.equal(openFiles.size, 0);
  console.log('OHOS record: current protocol, native start/errors, permissions, AAC, PCM/WAV, partial writes, dBFS, pause/resume, stream handshake/end and cleanup passed.');
} finally {
  for (const fd of openFiles.keys()) fs.closeSync(fd);
  fs.rmSync(folder, { recursive: true, force: true });
}
