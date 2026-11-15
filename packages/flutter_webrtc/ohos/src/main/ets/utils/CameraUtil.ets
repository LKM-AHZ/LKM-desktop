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

import camera from '@ohos.multimedia.camera';
import { BusinessError } from '@ohos.base';
import common from '@ohos.app.ability.common';
import { Log } from '@ohos/flutter_ohos';
import { display } from '@kit.ArkUI';
const TAG: string = 'FlutterWebRTCPlugin';

let cameraManager: camera.CameraManager
let previewOutput: camera.PreviewOutput;
let cameraInput: camera.CameraInput;
let captureSession: camera.PhotoSession;
let photoOutPut: camera.PhotoOutput;
let cameraArray: Array<camera.CameraDevice>;
let currentContext: common.BaseContext;

/**
 * 如果获取对象失败，说明相机可能被占用或无法使用。如果被占用，须等到相机被释放后才能重新获取。
 * @param context
 * @returns
 */
export function getCameraManager(context: common.BaseContext): camera.CameraManager {
  currentContext = context
  if (!cameraManager) {
    cameraManager = camera.getCameraManager(context);
  }
  return cameraManager;
}

/**
 * 通过cameraManager类中的getSupportedCameras()方法，获取当前设备支持的相机列表，列表中存储了设备支持的所有相机ID。
 * 若列表不为空，则说明列表中的每个ID都支持独立创建相机对象；否则，说明当前设备无可用相机，不可继续后续操作。
 * @param cameraManager
 * @returns
 */
export function getCameraDevices(cameraManager: camera.CameraManager): Array<camera.CameraDevice> {
  cameraArray = cameraManager.getSupportedCameras();
  if (cameraArray != undefined && cameraArray.length <= 0) {
    Log.e(TAG + '-CameraUtil', 'cameraManager.getSupportedCameras error');
    return [];
  }
  for (let index = 0; index < cameraArray.length; index++) {
    Log.i(TAG + '-CameraUtil', 'cameraId : ' + cameraArray[index].cameraId); // 获取相机ID
    Log.i(TAG + '-CameraUtil', 'cameraPosition : ' + cameraArray[index].cameraPosition); // 获取相机位置
    Log.i(TAG + '-CameraUtil', 'cameraType : ' + cameraArray[index].cameraType); // 获取相机类型
    Log.i(TAG + '-CameraUtil', 'connectionType : ' + cameraArray[index].connectionType); // 获取相机连接类型
  }
  return cameraArray;
}

/**
 * 调用cameraManager类中的createCaptureSession()方法创建一个会话
 * @param cameraManager
 * @returns
 */
export function getCaptureSession(cameraManager: camera.CameraManager): camera.Session | undefined {
  try {
    if (!captureSession) {
      captureSession = cameraManager.createSession(camera.SceneMode.NORMAL_VIDEO) as camera.PhotoSession;
    }
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to create the CaptureSession instance. error: ${JSON.stringify(err)}');
  }
  return captureSession;
}

/**
 * 调用captureSession类中的beginConfig()方法配置会话
 * @param captureSession
 */
export function beginConfig(captureSession: camera.Session): void {
  try {
    captureSession.beginConfig();
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to beginConfig. error: ${JSON.stringify(err)}');
  }
}

export function getCameraInput(cameraDevice: camera.CameraDevice,
  cameraManager: camera.CameraManager): camera.CameraInput | null {
  // 创建相机输入流
  try {
    cameraInput = cameraManager.createCameraInput(cameraDevice);
    // 监听cameraInput错误信息
    cameraInput.on('error', cameraDevice, (error: BusinessError) => {
      Log.i(TAG + '-CameraUtil', 'Camera input error code: ${error.code}');
    });
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to createCameraInput errorCode = ' + err.code);
  }

  return cameraInput;
}

/**
 * 通过getSupportedOutputCapability()方法，获取当前设备支持的所有输出流
 * 输出流在CameraOutputCapability中的各个profile字段中
 * @param cameraDevice
 * @param cameraManager
 * @returns
 */
export async function getSupportedOutputCapability(cameraDevice: camera.CameraDevice,
  cameraManager: camera.CameraManager,
  cameraInput: camera.CameraInput): Promise<camera.CameraOutputCapability | undefined> {
  // 打开相机
  await cameraInput.open();
  // 获取相机设备支持的输出流能力
  let cameraOutputCapability = cameraManager.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_PHOTO);
  if (!cameraOutputCapability) {
    Log.e(TAG + '-CameraUtil', 'cameraManager.getSupportedOutputCapability error');
    return undefined;
  }
  Log.i(TAG + '-CameraUtil', 'outputCapability: ' + JSON.stringify(cameraOutputCapability));
  return cameraOutputCapability;
}

/**
 * 获取预览流
 * @param cameraManager
 * @param cameraOutputCapability
 * @param surfaceId
 * @returns
 */
export function getPreviewOutput(cameraManager: camera.CameraManager,
  cameraOutputCapability: camera.CameraOutputCapability,
  surfaceId: string, cameraPosition: number): camera.PreviewOutput | undefined {
  let previewProfilesArray: Array<camera.Profile> = cameraOutputCapability.previewProfiles;
  try {
    previewOutput = cameraManager.createPreviewOutput(previewProfilesArray[0], surfaceId);
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to create the PreviewOutput instance. error code: ' + err.code);
  }
  return previewOutput;
}

export function setSessionCameraInput(captureSession: camera.Session, cameraInput: camera.CameraInput): void {
  try {
    captureSession.addInput(cameraInput);
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to addInput. error: ${JSON.stringify(err)}');
  }
}

export function setSessionPreviewOutput(captureSession: camera.Session, previewOutput: camera.PreviewOutput): void {
  try {
    captureSession.addOutput(previewOutput);
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to add previewOutput. error: ${JSON.stringify(err)}');
  }
}

/**
 * 调用captureSession类中的commitConfig()和start()方法提交相关配置，并启动会话
 * @param captureSession
 * @returns
 */
export async function startSession(captureSession: camera.Session): Promise<void> {
  try {
    await captureSession.commitConfig();
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to commitConfig. error: ${JSON.stringify(err)}');
  }

  try {
    await captureSession.start()
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to start. error: ${JSON.stringify(err)}');
  }
}

export async function stopSession(captureSession: camera.Session): Promise<void> {

  try {
    await captureSession.stop().then(() => {
      Log.i(TAG + '-CameraUtil', 'Promise returned to indicate the session stop success.');
    }).catch((error: BusinessError) => {
      Log.e(TAG + '-CameraUtil', 'Failed to stop the session, error code: ${error.code}.');
    });
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to stop. error: ${JSON.stringify(err)}');
  }
}

export async function releaseCamera(): Promise<void> {
  Log.i(TAG + '-CameraUtil', 'releaseCamera in!');
  if (captureSession) {
    captureSession.stop();
  }
  if (cameraInput) {
    cameraInput.close();
  }
  if (previewOutput) {
    previewOutput.release();
  }
  if (captureSession) {
    captureSession.release();
  }
  if (photoOutPut) {
    photoOutPut.release();
  }
  Log.i(TAG + '-CameraUtil', 'releaseCamera out!');
}

export async function setPhotoFlashMode(flashMode: number): Promise<void> {
  if (captureSession) {
    captureSession.setFlashMode(flashMode);
  }
}

export function getFlashMode(): camera.FlashMode | undefined {
  let flashMode: camera.FlashMode | undefined = undefined;
  try {
    getCaptureSession(cameraManager);
    flashMode = captureSession.getFlashMode();
  } catch (error) {
    // 失败返回错误码error.code并处理
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'The getFlashMode call failed.error code: ${err.code}');
  }
  return flashMode;
}

export function isTorchSupported(): boolean {
  let torchSupport: boolean = false;
  try {
    torchSupport = cameraManager.isTorchSupported();

  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to torch. errorCode = ' + err.code);
  }
  Log.i(TAG + '-CameraUtil', 'Returned with the torch support status:' + torchSupport);

  /*
   * 当使用后置摄像头并设置闪光灯模式FlashMode关闭时，手电筒功能无法启用。
   * 这里添加闪光灯模式查询判断，如果是关闭则开启。
   * */
  let isTorchModeSupport: boolean = false;
  try {
    isTorchModeSupport = cameraManager.isTorchModeSupported(camera.TorchMode.ON);
  } catch (error) {
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'Failed to set the torch mode. errorCode = ' + err.code);
  }
  Log.i(TAG + '-CameraUtil', 'Returned with the isTorchModeSupport :' + isTorchModeSupport);

  return torchSupport;
}

export function setTorchMode(torchMode: camera.FlashMode): boolean {
  try {
    getCaptureSession(cameraManager);
    captureSession.setFlashMode(torchMode);
    return true;
  } catch (error) {
    // 失败返回错误码error.code并处理
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'The setFlashMode call failed. error code: ${err.code}');
    return false;
  }
}

export async function switchCamera(cameraPosition: number, surfaceId: string, foldAbleStatus: number): Promise<void> {
  Log.i(TAG + '-CameraUtil', 'cameraPosition :' + cameraPosition);
  Log.i(TAG + '-CameraUtil', 'surfaceId :' + surfaceId);
  try {
    /*第一步先释放相机，再通过选择的相机position重新创建相机预览窗口*/
    releaseCamera();
    if (!cameraManager) {
      Log.e(TAG + '-CameraUtil', 'cameraManager error');
      return;
    }
    cameraArray = cameraManager.getSupportedCameras();
    if (cameraArray.length <= 0) {
      Log.e(TAG + '-CameraUtil', 'cameraManager.getSupportedCameras error');
      return;
    }
    cameraInput = cameraManager.createCameraInput(cameraArray[cameraPosition]);
    await cameraInput.open();
    let sceneModes: camera.SceneMode[] = cameraManager.getSupportedSceneModes(cameraArray[cameraPosition]);
    let cameraOutputCap: camera.CameraOutputCapability =
      cameraManager.getSupportedOutputCapability(cameraArray[cameraPosition], camera.SceneMode.NORMAL_PHOTO);
    let isSupportPhotoMode: boolean = sceneModes.indexOf(camera.SceneMode.NORMAL_PHOTO) >= 0;
    if (!isSupportPhotoMode) {
      Log.e(TAG + '-CameraUtil', 'isSupportPhotoMode error');
      return;
    }
    if (!cameraOutputCap) {
      Log.e(TAG + '-CameraUtil', 'cameraManager.getSupportedOutputCapability error');
      return;
    }
    let previewProfilesArray: camera.Profile[] = cameraOutputCap.previewProfiles;
    let photoProfilesArray: camera.Profile[] = cameraOutputCap.photoProfiles;
    let previewProfile: undefined | camera.Profile = previewProfilesArray.find((profile: camera.Profile) => {
      let screen = display.getDefaultDisplaySync();
      if (screen.width <= 1080) {
        return profile.size.height === 1080 && profile.size.width === 1440;
      } else if (screen.width <= 1440 && screen.width > 1080) {
        return profile.size.height === 1440 && profile.size.width === 1920;
      }
      return profile.size.height <= screen.width &&
        profile.size.height >= 1080 &&
        (profile.size.width / profile.size.height) < (screen.height / screen.width) &&
        (profile.size.width / profile.size.height) >
          (foldAbleStatus === display.FoldStatus.FOLD_STATUS_EXPANDED ? 1 : 4 / 3);
    });
    let photoProfile: undefined | camera.Profile = photoProfilesArray.find((profile: camera.Profile) => {
      if (previewProfile) {
        return profile.size.width <= 4096 &&
          profile.size.width >= 2448 &&
          profile.size.height === (foldAbleStatus === display.FoldStatus.FOLD_STATUS_EXPANDED ? 1 :
            (previewProfile.size.height / previewProfile.size.width)) * profile.size.width;
      }
      return undefined;
    });
    previewOutput = cameraManager.createPreviewOutput(previewProfile, surfaceId);
    if (previewOutput === undefined) {
      Log.e(TAG + '-CameraUtil', 'cameraManager.createPreviewOutput error');
      return;
    }
    photoOutPut = cameraManager.createPhotoOutput(photoProfile);
    if (photoOutPut === undefined) {
      Log.e(TAG + '-CameraUtil', 'cameraManager.createPhotoOutput error');
      return;
    }
    captureSession = cameraManager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
    if (captureSession === undefined) {
      Log.e(TAG + '-CameraUtil', 'cameraManager.createSession error');
      return;
    }
    Log.i(TAG + '-CameraUtil', 'captureSession.beginConfig()!');
    captureSession.beginConfig();
    captureSession.addInput(cameraInput);
    captureSession.addOutput(previewOutput);
    captureSession.addOutput(photoOutPut);
    Log.i(TAG + '-CameraUtil', 'begin captureSession.commitConfig()!');
    await captureSession.commitConfig();
    await captureSession.start();
    Log.i(TAG + '-CameraUtil', 'after captureSession.start()!');

  } catch (error) {
    // 失败返回错误码error.code并处理
    let err = error as BusinessError;
    Log.e(TAG + '-CameraUtil', 'The setFlashMode call failed. error code: ${err.code}');
  }
}

export async function setZoom(zoomLevel: number): Promise<boolean> {
  Log.i(TAG + '-CameraUtil', 'setZoom in!');
  getCaptureSession(cameraManager);
  if (captureSession === undefined) {
    Log.e(TAG + '-CameraUtil', 'captureSession is bull');
    return false;
  }
  captureSession.setZoomRatio(zoomLevel);
  Log.i(TAG + '-CameraUtil', 'setZoom out!');
  return true;
}