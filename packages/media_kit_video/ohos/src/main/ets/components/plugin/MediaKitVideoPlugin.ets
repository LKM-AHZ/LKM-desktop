// OHOS texture transport based on CPF-Flutter media_kit d424290.
import { FlutterPlugin, FlutterPluginBinding, MethodCallHandler, MethodCall, MethodResult,
  MethodChannel, TextureRegistry, SurfaceTextureEntry } from '@ohos/flutter_ohos';

export default class MediaKitVideoPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private registry: TextureRegistry | null = null;
  private outputs: Map<string, SurfaceTextureEntry> = new Map();
  getUniqueClassName(): string { return 'MediaKitVideoPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.registry = binding.getTextureRegistry();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'com.alexmercerind/media_kit_video');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.channel = null;
    for (const entry of this.outputs.values()) this.registry?.unregisterTexture(entry.getTextureId());
    this.outputs.clear(); this.registry = null;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      const registry = this.registry;
      if (registry === null) throw new Error('Video engine is detached');
      const handle = call.argument('handle') as string;
      if (handle == null || !/^[0-9]+$/.test(handle) || handle === '0') throw new Error('Invalid player handle');
      switch (call.method) {
        case 'VideoOutputManager.Create': {
          if (this.outputs.has(handle)) throw new Error('Video output already exists');
          const entry = registry.registerTexture(registry.getTextureId());
          this.outputs.set(handle, entry);
          result.success(new Map<string, Object>([['id', entry.getTextureId()], ['wid', entry.getSurfaceId().toString()]]));
          return;
        }
        case 'VideoOutputManager.SetSurfaceSize': {
          const entry = this.outputs.get(handle);
          if (entry === undefined) throw new Error('Video output does not exist');
          const width = Number(call.argument('width')); const height = Number(call.argument('height'));
          if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 ||
            width > 16384 || height > 16384) throw new Error('Invalid surface size');
          registry.notifyTextureResizing(entry.getTextureId(), width, height);
          result.success(null); return;
        }
        case 'VideoOutputManager.Dispose': {
          const entry = this.outputs.get(handle);
          if (entry !== undefined) { registry.unregisterTexture(entry.getTextureId()); this.outputs.delete(handle); }
          result.success(null); return;
        }
        default: result.notImplemented();
      }
    } catch (error) { result.error('video_output_error', (error as Error).message, null); }
  }
}
