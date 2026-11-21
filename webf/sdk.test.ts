import { afterEach, expect, test, vi } from 'vitest';
import { miniApp } from './sdk';

afterEach(() => vi.unstubAllGlobals());

test('SDK serializes snapshots and propagates host failures without losing edits', async () => {
  const invokeMethod = vi.fn().mockResolvedValue(JSON.stringify({ ok: true, data: true }));
  vi.stubGlobal('window', { webf: { methodChannel: { invokeMethod } } });
  await miniApp.save([{ text: 'offline note' }]);
  expect(invokeMethod).toHaveBeenCalledWith('save', '[{"text":"offline note"}]');
  invokeMethod.mockResolvedValue(JSON.stringify({ ok: true, data: '[{"text":"offline note"}]' }));
  expect(await miniApp.load()).toEqual([{ text: 'offline note' }]);
  invokeMethod.mockResolvedValue(JSON.stringify({ ok: true, data: null }));
  expect(await miniApp.load()).toBeNull();
  invokeMethod.mockResolvedValue(JSON.stringify({ ok: false, error: 'session' }));
  await expect(miniApp.save([])).rejects.toThrow('session');
});
