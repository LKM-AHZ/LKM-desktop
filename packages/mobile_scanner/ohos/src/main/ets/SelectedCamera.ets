// CameraKit owns capture when ScanKit's customScan (rear only) cannot select a camera.
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { detectBarcode, scanBarcode, customScan } from '@kit.ScanKit';
import common from '@ohos.app.ability.common';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';

export class SelectedCamera {
  private input: camera.CameraInput | null = null;
  private session: camera.PhotoSession | null = null;
  private preview: camera.PreviewOutput | null = null;
  private analysis: camera.PreviewOutput | null = null;
  private receiver: image.ImageReceiver | null = null;
  private reads: Set<Promise<void>> = new Set();
  get processing(): Promise<void> { return Promise.all(Array.from(this.reads)).then((): void => {}); }
  private busy: boolean = false;
  private closed: boolean = false;
  private lastFrame: number = 0;
  private started: boolean = false;
  private starting: Promise<void> = Promise.resolve();
  private closing: Promise<void> | null = null;
  private width: number = 0;
  private height: number = 0;
  rotation: number = 0;
  cameraCount: number = 0;
  torchable: boolean = false;
  torch: boolean = false;

  private scanCallback: AsyncCallback<scanBarcode.ScanResult[]>;
  private frameCallback: AsyncCallback<customScan.ScanFrame>;

  constructor(scanCallback: AsyncCallback<scanBarcode.ScanResult[]>,
    frameCallback: AsyncCallback<customScan.ScanFrame>) {
    this.scanCallback = scanCallback;
    this.frameCallback = frameCallback;
  }

  start(context: common.BaseContext, facing: number, surface: string, options: scanBarcode.ScanOptions,
    resolution: number[] | undefined, timeout: number, zoom: number, torch: boolean, autoZoom: boolean): Promise<void> {
    this.starting = this.open(context, facing, surface, options, resolution, timeout, zoom, torch, autoZoom);
    return this.starting;
  }
  private async open(context: common.BaseContext, facing: number, surface: string, options: scanBarcode.ScanOptions,
    resolution: number[] | undefined, timeout: number, zoom: number, torch: boolean, autoZoom: boolean): Promise<void> {
    const manager = camera.getCameraManager(context);
    const devices = manager.getSupportedCameras();
    this.cameraCount = devices.length;
    const device = devices.find(device => facing === 0
      ? device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT
      : device.connectionType === camera.ConnectionType.CAMERA_CONNECTION_USB_PLUGIN ||
        device.connectionType === camera.ConnectionType.CAMERA_CONNECTION_REMOTE);
    if (device === undefined) throw new Error('Requested camera is not connected or available');
    const profiles = manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO).previewProfiles
      .filter(profile => profile.format === camera.CameraFormat.CAMERA_FORMAT_YUV_420_SP &&
        profile.size.width % 2 === 0 && profile.size.height % 2 === 0);
    const targetWidth = resolution?.[0] ?? 640;
    const targetHeight = resolution?.[1] ?? 480;
    profiles.sort((a, b) => Math.abs(a.size.width * a.size.height - targetWidth * targetHeight) -
      Math.abs(b.size.width * b.size.height - targetWidth * targetHeight));
    if (profiles.length === 0) throw new Error('Requested camera has no NV21 analysis preview profile');
    const profile = profiles[0];
    this.width = profile.size.width; this.height = profile.size.height;
    this.input = manager.createCameraInput(device);
    await this.input.open();
    if (this.closed) throw new Error('Camera detached during startup');
    // The receiver's nominal JPEG component carries the actual preview producer's NV21 bytes (SDK Image docs).
    this.receiver = image.createImageReceiver(profile.size, image.ImageFormat.JPEG, 2);
    this.preview = manager.createPreviewOutput(profile, surface);
    this.analysis = manager.createPreviewOutput(profile, await this.receiver.getReceivingSurfaceId());
    this.session = manager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
    this.session.beginConfig();
    this.session.addInput(this.input);
    if (!this.session.canAddOutput(this.preview)) throw new Error('Camera cannot provide preview output');
    this.session.addOutput(this.preview);
    if (!this.session.canAddOutput(this.analysis)) throw new Error('Camera cannot provide simultaneous preview and analysis');
    this.session.addOutput(this.analysis);
    await this.session.commitConfig();
    this.rotation = this.preview.getPreviewRotation(display.getDefaultDisplaySync().rotation);
    this.preview.setPreviewRotation(this.rotation, true);
    this.torchable = this.session.hasFlash();
    if (torch && !this.torchable) throw new Error('Requested camera has no flashlight');
    this.setTorch(torch);
    this.setZoom(zoom);
    this.receiver.on('imageArrival', (): void => {
      if (this.closed) return;
      // Drain every arriving buffer, even while ScanKit is busy, to avoid blocking the camera producer.
      const pending = this.consume(options, timeout, autoZoom).catch((error: BusinessError): void => {
        if (!this.closed) this.scanCallback({ name: error.name, code: error.code ?? 7400201, message: error.message }, []);
      });
      this.reads.add(pending);
      pending.then((): void => { this.reads.delete(pending); });
    });
    await this.session.start(); this.started = true;
    if (this.closed) throw new Error('Camera detached during startup');
  }
  get previewWidth(): number { return this.rotation % 180 === 0 ? this.width : this.height; }
  get previewHeight(): number { return this.rotation % 180 === 0 ? this.height : this.width; }
  point(x: number, y: number): camera.Point {
    if (this.rotation === 90) return { x: this.height - y, y: x };
    if (this.rotation === 180) return { x: this.width - x, y: this.height - y };
    if (this.rotation === 270) return { x: y, y: this.width - x };
    return { x, y };
  }
  private async consume(options: scanBarcode.ScanOptions, timeout: number, autoZoom: boolean): Promise<void> {
    let frame: image.Image | null = null;
    let analyzing = false;
    try {
      frame = await this.receiver!.readNextImage();
      if (this.closed || this.busy || Date.now() - this.lastFrame < timeout) return;
      this.busy = true; analyzing = true;
      this.lastFrame = Date.now();
      const component = await frame.getComponent(image.ComponentType.JPEG);
      const source = new Uint8Array(component.byteBuffer);
      const stride = component.rowStride || this.width;
      const rows = this.height * 3 / 2;
      if (stride < this.width || source.length !== stride * rows) throw new Error('Camera returned an unsupported NV21 buffer layout');
      const bytes = new Uint8Array(this.width * rows);
      for (let row = 0; row < rows; row++) bytes.set(source.subarray(row * stride, row * stride + this.width), row * this.width);
      // Do not retain an ImageReceiver buffer during asynchronous decoding/packing.
      await frame.release(); frame = null;
      if (this.closed) return;
      await this.frameCallback(undefined, { byteBuffer: bytes.buffer, width: this.width, height: this.height });
      const result = await detectBarcode.decodeImage({ byteBuffer: bytes.buffer, width: this.width,
        height: this.height, format: detectBarcode.ImageFormat.NV21 }, options);
      if (this.closed) return;
      if (autoZoom && result.zoomValue > 1 && this.session !== null) {
        const range = this.session.getZoomRatioRange();
        this.setZoom(Math.min(range[range.length - 1], this.session.getZoomRatio() * result.zoomValue));
      }
      await this.scanCallback(undefined, result.scanResults);
    } catch (error) {
      if (!this.closed) {
        const failure = error as BusinessError;
        this.scanCallback({ name: failure.name, code: failure.code ?? 7400201, message: failure.message }, []);
      }
    } finally {
      try { await frame?.release(); } finally { if (analyzing) this.busy = false; }
    }
  }
  setTorch(enabled: boolean): void {
    if (this.session === null) throw new Error('Camera is not running');
    if (!this.torchable) {
      if (enabled) throw new Error('Requested camera has no flashlight');
      return;
    }
    const mode = enabled ? camera.FlashMode.FLASH_MODE_ALWAYS_OPEN : camera.FlashMode.FLASH_MODE_CLOSE;
    if (!this.session.isFlashModeSupported(mode)) throw new Error('Requested flashlight mode is unsupported');
    this.session.setFlashMode(mode); this.torch = enabled;
  }
  setZoom(value: number): void {
    if (this.session === null) throw new Error('Camera is not running');
    const range = this.session.getZoomRatioRange();
    if (!Number.isFinite(value) || value < range[0] || value > range[range.length - 1]) throw new Error('Zoom outside camera range');
    this.session.setZoomRatio(value);
  }
  setFocus(x: number, y: number): void {
    if (this.session === null) throw new Error('Camera is not running');
    if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) throw new Error('Invalid focus point');
    if (!this.session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_AUTO)) throw new Error('Camera autofocus is unsupported');
    this.session.setFocusMode(camera.FocusMode.FOCUS_MODE_AUTO);
    this.session.setFocusPoint({ x, y });
  }
  close(): Promise<void> {
    if (this.closing === null) this.closing = this.teardown();
    return this.closing;
  }
  private async teardown(): Promise<void> {
    this.closed = true;
    await this.starting.catch((): void => {});
    this.receiver?.off('imageArrival');
    let failure: Error | null = null;
    try { if (this.started) await this.session?.stop(); } catch (error) { failure = error as Error; }
    await this.processing;
    try { await this.session?.release(); } catch (error) { failure = error as Error; }
    try { await this.preview?.release(); } catch (error) { failure = error as Error; }
    try { await this.analysis?.release(); } catch (error) { failure = error as Error; }
    try { await this.input?.close(); } catch (error) { failure = error as Error; }
    try { await this.receiver?.release(); } catch (error) { failure = error as Error; }
    this.session = null; this.input = null; this.preview = null; this.analysis = null; this.receiver = null;
    if (failure !== null) throw failure;
  }
}
