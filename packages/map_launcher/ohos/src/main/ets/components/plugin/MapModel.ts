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

/** MapModel **/
export class MapModel {
  mapType: String | null = null;
  mapName: String | null = null;
  packageName: String | null = null;
  urlPrefix: String | null = null;

  constructor(mapType: String, mapName: String, packageName: String, urlPrefix: String) {
    this.mapType = mapType;
    this.mapName = mapName;
    this.packageName = packageName;
    this.urlPrefix = urlPrefix;
  }

  toMap(): Map<String, String> {
    let tempMap = new Map<String, String>();
    tempMap.set('mapType', this.mapType);
    tempMap.set('mapName', this.mapName);
    tempMap.set('packageName', this.packageName);
    tempMap.set('urlPrefix', this.urlPrefix);
    return tempMap;
  }
}