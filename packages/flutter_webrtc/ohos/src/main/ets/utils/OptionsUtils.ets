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

import { Any } from '@ohos/flutter_ohos';
import { AdapterType } from './AdapterType';
import { ConstraintsMap } from './ConstraintsMap';
import { DataArray, DataMap, ObjectType } from './ObjectType';
import { ArrayList } from '@kit.ArkTS';

export function getOptionsNetworkIgnoreMask(optionsMap: ConstraintsMap): number {
  let networkIgnoreMask: number = AdapterType.ADAPTER_TYPE_UNKNOWN;
  if (optionsMap.getType('networkIgnoreMask') === ObjectType.Array) {
    let ignoredAdapters = optionsMap.getArray('networkIgnoreMask')!;
    ignoredAdapters.toArrayList().forEach((adapter: Any) => {
      switch (adapter?.toString()) {
        case 'adapterTypeEthernet':
          networkIgnoreMask += AdapterType.ADAPTER_TYPE_ETHERNET;
          break;
        case 'adapterTypeWifi':
          networkIgnoreMask += AdapterType.ADAPTER_TYPE_WIFI;
          break;
        case 'adapterTypeCellular':
          networkIgnoreMask += AdapterType.ADAPTER_TYPE_CELLULAR;
          break;
        case 'adapterTypeVpn':
          networkIgnoreMask += AdapterType.ADAPTER_TYPE_VPN;
          break;
        case 'adapterTypeLoopback':
          networkIgnoreMask += AdapterType.ADAPTER_TYPE_LOOPBACK;
          break;
        case 'adapterTypeAny':
          networkIgnoreMask += AdapterType.ADAPTER_TYPE_ANY;
          break;
      }
    })
  }
  return networkIgnoreMask;
}

export function getOptionsForceSWCodec(optionsMap: ConstraintsMap): boolean {
  let forceSWCodec: boolean = false;
  if (optionsMap.getType('forceSWCodec') === ObjectType.Boolean) {
    forceSWCodec = optionsMap.getBoolean('forceSWCodec');
  }
  return forceSWCodec;
}

export function getOptionsForceSWCodecList(optionsMap: ConstraintsMap): ArrayList<String> {
  let forceSWCodecList: ArrayList<String> = new ArrayList();
  if (optionsMap.getType('forceSWCodecList') === ObjectType.Array) {
    let array: DataArray = optionsMap.getListArray('forceSWCodecList');
    array.forEach((v: Any) => {
      forceSWCodecList.add(v?.toString());
    })
  } else {
    // disable HW Codec for VP9 by default.
    forceSWCodecList.add('VP9');
  }
  return forceSWCodecList;
}

export function getOptionsAudioConfiguration(optionsMap: ConstraintsMap): ConstraintsMap {
  let audioConfiguration: ConstraintsMap = new ConstraintsMap()
  if (optionsMap.getType('androidAudioConfiguration') === ObjectType.Map) {
    audioConfiguration = optionsMap.getMap('androidAudioConfiguration')!;
  }
  return audioConfiguration;
}
