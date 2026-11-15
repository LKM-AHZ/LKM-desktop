/* Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND. See the License for the specific language governing
 * permissions and limitations under the License.
 */
import { Any } from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';

export class StateEvents implements StreamHandler {
  private sink: EventSink | null = null;
  state: number = 2; // record 7: pause=0, record=1, stop=2.
  onListen(args: Any, sink: EventSink): void { this.sink = sink; sink.success(this.state); }
  onCancel(args: Any): void { this.sink = null; }
  send(state: number): void { this.state = state; this.sink?.success(state); }
  error(message: string): void { this.sink?.error('record_error', message, null); }
}

export class DataEvents implements StreamHandler {
  private sink: EventSink | null = null;
  private pending: Uint8Array[] = [];
  private size: number = 0;
  private ended: boolean = false;
  reset(): void { this.sink = null; this.pending = []; this.size = 0; this.ended = false; }
  onListen(args: Any, sink: EventSink): void {
    this.sink = sink;
    for (const bytes of this.pending) sink.success(bytes);
    this.pending = []; this.size = 0;
    if (this.ended) sink.endOfStream();
  }
  onCancel(args: Any): void { this.sink = null; }
  send(bytes: Uint8Array): void {
    if (this.sink !== null) { this.sink.success(bytes); return; }
    // ponytail: only buffer the start/listen handshake; fail at 1 MiB rather than grow indefinitely.
    if (this.size + bytes.byteLength > 1048576) throw new Error('Recording stream has no consumer');
    this.pending.push(bytes); this.size += bytes.byteLength;
  }
  end(): void { this.ended = true; this.sink?.endOfStream(); }
  error(message: string): void { this.sink?.error('record_error', message, null); }
}
