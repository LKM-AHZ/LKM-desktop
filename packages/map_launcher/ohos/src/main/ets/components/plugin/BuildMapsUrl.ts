/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import bundleManager from '@ohos.bundle.bundleManager';

/** BuildMapsUrl **/
export class BuildMapsUrl {
  mapType: String | null = null;
  title: String | null = null;
  latitude: String | null = null;
  longitude: String | null = null;
  url: String | null = null;
  dTitle: String | null = null;
  destinationLatitude: String | null = null;
  destinationLongitude: String | null = null;
  directionsMode: String;
  isMarker: boolean | null = null;

  constructor(mapType: string | null, title: string | null, latitude: string | null, longitude: string | null,
    url: string | null, dTitle: string | null, destinationLatitude: string | null,
    destinationLongitude: string | null, directionsMode: string, isMarker: boolean | true) {
    this.mapType = mapType;
    this.title = title;
    this.latitude = latitude;
    this.longitude = longitude;
    this.url = url;
    this.dTitle = dTitle;
    this.destinationLatitude = destinationLatitude;
    this.destinationLongitude = destinationLongitude;
    this.directionsMode = directionsMode;
    this.isMarker = isMarker;
  }

  getUrl(mapType: string): string {
    let flag = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO;
    let bundleInfo = bundleManager.getBundleInfoForSelfSync(flag);
    let appName = bundleInfo.name;

    let rawUrl: string = this.url?.toString() ?? '';
    let decodedUrl: string = rawUrl;
    try {
      decodedUrl = decodeURIComponent(rawUrl);
    } catch (e) {
      decodedUrl = rawUrl;
    }

    switch (mapType) {
      case 'gaoDe':
        let t = this.getDirectionsMode(this.directionsMode, mapType);
        let sname = this.title ? encodeURIComponent(this.title.toString()) : '';
        let dname = this.dTitle ? encodeURIComponent(this.dTitle.toString()) : '';
        let buildUrl = 'amapuri://route/plan/?sourceApplication=' + encodeURIComponent(appName)
          + '&dlat=' + this.destinationLatitude
          + '&dlon=' + this.destinationLongitude
          + '&dname=' + dname
          + '&slat=' + this.latitude
          + '&slon=' + this.longitude
          + '&sname=' + sname
          + '&t=' + t
          + '&dev=0';
        console.info('[BuildMapsUrl] mapType=' + mapType
          + ' directionsMode=' + this.directionsMode
          + ' mappedT=' + t
          + ' url=' + buildUrl);

        return buildUrl;
      case 'baidu': {
        return decodedUrl;
      }
      case 'tencent': {
        return decodedUrl;
      }
      default: {
        return decodedUrl;
      }
    }
  }

  getDirectionsMode(directionsMode: String, mapType: string) {
    switch (directionsMode) {
      // Amap / Gaode scheme parameter: t=0 driving, 1 transit, 2 walking, 3 bicycling
      case 'driving': {
        console.info('[BuildMapsUrl] getDirectionsMode mapType=' + mapType + ' input=' + directionsMode + ' -> 0');
        return 0;
      }
      case 'walking': {
        if (mapType == 'petal') {
          return 1;
        }
        if (mapType == 'gaoDe') {
          return 2;
        }
        console.info('[BuildMapsUrl] getDirectionsMode mapType=' + mapType + ' input=' + directionsMode +
          ' -> 0 (fallback)');
        return 0;
      }
      case 'transit': {
        console.info('[BuildMapsUrl] getDirectionsMode mapType=' + mapType + ' input=' + directionsMode + ' -> 1');
        if (mapType == 'petal') return 3;
        return 1;
      }
      case 'bicycling': {
        if (mapType == 'petal') return 2;
        if (mapType == 'gaoDe') return 3;
        console.info('[BuildMapsUrl] getDirectionsMode mapType=' + mapType + ' input=' + directionsMode + ' -> 0 (fallback)');
        return 0;
      }
      default: {
        console.info('[BuildMapsUrl] getDirectionsMode mapType=' + mapType + ' input=' + directionsMode + ' -> 0 (default)');
        return 0;
      }
    }
  }
}

