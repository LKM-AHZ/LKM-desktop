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

import { DataMap } from './ObjectType';
import { DataArray, ObjectType } from './ObjectType';

class ConstraintsArray {
  private mArray: DataArray;

  constructor(array?: DataArray) {
    if (array) {
      this.mArray = array;
    } else {
      this.mArray = new Array<ESObject>();
    }
  }

  public size(): number {
    return this.mArray.length;
  }

  public isNull(index: number): boolean {
    return this.mArray[index] === null;
  }

  public getBoolean(index: number): boolean {
    return this.mArray[index] as boolean;
  }

  public getNumber(index: number): number {
    return this.mArray[index] as number;
  }

  public getString(index: number): string {
    return this.mArray[index] as string;
  }

  public getByte(index: number): Uint8Array {
    return this.mArray[index] as Uint8Array;
  }

  public getArray(index: number): ConstraintsArray {
    return new ConstraintsArray(this.mArray[index] as DataArray);
  }

  public getMap(index: number): DataMap {
    return this.mArray[index] as DataMap;
  }

  public getType(index: number): ObjectType {
    const object = this.mArray[index];
    if (object === null) {
      return ObjectType.Null;
    } else if (object instanceof Boolean || typeof object === 'boolean') {
      return ObjectType.Boolean;
    } else if (object instanceof Number || typeof object === 'number') {
      return ObjectType.Number;
    } else if (object instanceof String || typeof object === 'string') {
      return ObjectType.String;
    } else if (object instanceof Array) {
      return ObjectType.Array;
    } else if (object instanceof Map) {
      return ObjectType.Map;
    } else if (object instanceof Uint8Array) {
      return ObjectType.Byte;
    }
    return ObjectType.Null;
  }

  public toArrayList(): DataArray {
    return this.mArray;
  }

  public pushNull(): void {
    this.mArray.push(null);
  }

  public pushBoolean(value: boolean): void {
    this.mArray.push(value);
  }

  public pushNumber(value: number): void {
    this.mArray.push(value);
  }

  public pushString(value: string): void {
    this.mArray.push(value);
  }

  public pushArray(array: ConstraintsArray): void {
    this.mArray.push(array.toArrayList());
  }

  public pushByte(value: Uint8Array): void {
    this.mArray.push(value);
  }

  public pushMap(map: DataMap): void {
    this.mArray.push(map);
  }

  public toString(): string {
    return `${JSON.stringify(this.mArray)}`;
  }
}

export { ConstraintsArray };