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

import { FlutterPlugin, FlutterPluginBinding, MethodChannel, MethodCallHandler, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export default class GeocodingOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private pending: Set<MethodResult> = new Set();
  getUniqueClassName(): string { return 'GeocodingOhosPlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'flutter.baseflow.com/geocoding');
    this.channel.setMethodCallHandler(this);
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null); this.channel = null;
    for (const result of this.pending) result.error('IO_ERROR', 'Geocoding engine detached', null);
    this.pending.clear();
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (!['isPresent','locationFromAddress','placemarkFromAddress','placemarkFromCoordinates'].includes(call.method)) {
      result.notImplemented(); return;
    }
    if (this.channel === null) { result.error('IO_ERROR', 'Geocoding engine detached', null); return; }
    this.pending.add(result);
    this.query(call).then((value: Object) => {
      if (this.pending.delete(result)) result.success(value);
    }).catch((error: BusinessError) => {
      if (this.pending.delete(result)) result.error('IO_ERROR', error.message, error.code ?? null);
    });
  }
  private async query(call: MethodCall): Promise<Object> {
    if (call.method === 'isPresent') return geoLocationManager.isGeocoderAvailable();
    const locale = call.argument('localeIdentifier') as string;
    let addresses: geoLocationManager.GeoAddress[];
    if (call.method === 'placemarkFromCoordinates') {
      const latitude = call.argument('latitude') as number;
      const longitude = call.argument('longitude') as number;
      if (!Number.isFinite(latitude) || Math.abs(latitude) > 90 ||
        !Number.isFinite(longitude) || Math.abs(longitude) > 180) throw new Error('Invalid coordinates');
      const request: geoLocationManager.ReverseGeoCodeRequest = { latitude, longitude, maxItems: 5 };
      if (locale != null) request.locale = locale;
      addresses = await geoLocationManager.getAddressesFromLocation(request);
    } else {
      const address = call.argument('address') as string;
      if (address == null || address.trim() === '') throw new Error('Empty address');
      const request: geoLocationManager.GeoCodeRequest = { description: address, maxItems: 5 };
      if (locale != null) request.locale = locale;
      addresses = await geoLocationManager.getAddressesFromLocationName(request);
    }
    const rows: Map<string, Object>[] = [];
    for (const address of addresses) {
      const row = new Map<string, Object>();
      if (call.method === 'locationFromAddress') {
        if (address.latitude == null || address.longitude == null) continue;
        row.set('latitude', address.latitude); row.set('longitude', address.longitude);
      } else {
        const fields: Map<string, string | undefined> = new Map([
          ['name', address.placeName], ['street', address.roadName], ['isoCountryCode', address.countryCode],
          ['country', address.countryName], ['postalCode', address.postalCode],
          ['administrativeArea', address.administrativeArea], ['subAdministrativeArea', address.subAdministrativeArea],
          ['locality', address.locality], ['subLocality', address.subLocality],
          ['thoroughfare', address.roadName], ['subThoroughfare', address.subRoadName],
        ]);
        fields.forEach((value: string | undefined, key: string) => { if (value != null) row.set(key, value); });
      }
      rows.push(row);
    }
    return rows;
  }
}
