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

import { ConstraintsArray } from './ConstraintsArray';
import { DataMap, DataArray, ObjectType } from './ObjectType';

class ConstraintsMap {
  private mMap: DataMap;

  constructor(map?: DataMap) {
    if (map) {
      this.mMap = map;
    } else {
      this.mMap = new Map<string, ESObject>();
    }
  }

  public toMap(): DataMap {
    return this.mMap;
  }

  public hasKey(name: string): boolean {
    return this.mMap.has(name);
  }

  public isNull(name: string): boolean {
    return this.mMap.get(name) === null;
  }

  public get(name: string): ESObject {
    return this.mMap.get(name);
  }

  public getBoolean(name: string): boolean {
    return this.mMap.get(name) as boolean;
  }

  public getDouble(name: string): number {
    return this.mMap.get(name) as number;
  }

  public getNumber(name: string): number {
    if (this.getType(name) === ObjectType.String) {
      return parseInt(this.mMap.get(name) as string, 10);
    }
    return this.mMap.get(name) as number;
  }

  public getString(name: string): string {
    return this.mMap.get(name) as string;
  }

  public getMap(name: string): ConstraintsMap | null {
    const value = this.mMap.get(name);
    if (!value) {
      return null;
    }
    return new ConstraintsMap(value as DataMap);
  }

  public getType(name: string): ObjectType {
    const value = this.mMap.get(name);
    if (value === null) {
      return ObjectType.Null;
    } else if (value instanceof Number || typeof value === 'number') {
      return ObjectType.Number;
    } else if (value instanceof String || typeof value === 'string') {
      return ObjectType.String;
    } else if (value instanceof Boolean || typeof value === 'boolean') {
      return ObjectType.Boolean;
    } else if (value instanceof Map) {
      return ObjectType.Map;
    } else if (value instanceof Array) {
      return ObjectType.Array;
    } else if (value instanceof Uint8Array) {
      return ObjectType.Byte;
    } else {
      return ObjectType.Null;
    }
  }

  public putBoolean(key: string, value: boolean): void {
    this.mMap.set(key, value);
  }

  public putNumber(key: string, value: number): void {
    this.mMap.set(key, value);
  }

  public putString(key: string, value: string): void {
    this.mMap.set(key, value);
  }

  public putByte(key: string, value: Uint8Array): void {
    this.mMap.set(key, value);
  }

  public putNull(key: string): void {
    this.mMap.set(key, null);
  }

  public putMap(key: string, value: DataMap): void {
    this.mMap.set(key, value);
  }

  public merge(value: DataMap): void {
    value.forEach((v, k) => this.mMap.set(k, v));
  }

  public putArray(key: string, value: DataArray): void {
    this.mMap.set(key, value);
  }

  public getArray(name: string): ConstraintsArray | null {
    const value = this.mMap.get(name);
    if (!value) {
      return null;
    }
    return new ConstraintsArray(value as DataArray);
  }

  public getListArray(name: string): DataArray {
    return this.mMap.get(name) as DataArray;
  }

  public toString(): string {
    return `${JSON.stringify(Object.fromEntries(this.mMap))}`;
  }
}

export { ConstraintsMap };