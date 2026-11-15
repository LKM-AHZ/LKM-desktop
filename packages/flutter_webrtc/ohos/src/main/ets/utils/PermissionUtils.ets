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

import bundleManager from '@ohos.bundle.bundleManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';
import common from '@ohos.app.ability.common';
import { ConstraintsMap } from './ConstraintsMap';
export type ResultCallback = (errCode: string | null, errDesc: string | null) => void;
export class PermissionsManager {
  private static instance: PermissionsManager;
  private commonContext: common.UIAbilityContext | null = null;
  static getInstance(): PermissionsManager {
    if (!PermissionsManager.instance) PermissionsManager.instance = new PermissionsManager();
    return PermissionsManager.instance;
  }
  init(context: common.UIAbilityContext | null): void { this.commonContext = context; }
  async requestPermissions(permissions: Permissions[], callback: ResultCallback): Promise<void> {
    try {
      const context = this.commonContext;
      if (context === null) { callback('no_ability', 'Recording ability detached'); return; }
      if (await this.checkPermissions(permissions)) {
        if (this.commonContext !== context) callback('no_ability', 'Recording ability detached');
        else callback(null, null);
        return;
      }
      const data = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions);
      if (this.commonContext !== context) { callback('no_ability', 'Recording ability detached'); return; }
      if (data.authResults.length !== permissions.length || data.authResults.some((status: number) => status !== 0)) {
        callback('permission_denied', 'Camera or microphone permission denied'); return;
      }
      callback(null, null);
    } catch (error) {
      const failure = error as BusinessError;
      callback(String(failure.code ?? 'permission_error'), failure.message);
    }
  }
  async checkPermissions(permissions: Permissions[]): Promise<boolean> {
    for (const permission of permissions) {
      if (await this.checkAccessToken(permission) !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) return false;
    }
    return true;
  }
  async checkAccessToken(permission: Permissions): Promise<abilityAccessCtrl.GrantStatus> {
    const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    return await abilityAccessCtrl.createAtManager().checkAccessToken(info.appInfo.accessTokenId, permission);
  }
  async processPermissions(constraints: ConstraintsMap, callback: ResultCallback): Promise<void> {
    const permissions: Permissions[] = [];
    if (constraints.hasKey('audio') && constraints.toMap().get('audio') !== false) permissions.push('ohos.permission.MICROPHONE');
    if (constraints.hasKey('video') && constraints.toMap().get('video') !== false) permissions.push('ohos.permission.CAMERA');
    await this.requestPermissions(permissions, callback);
  }
}
