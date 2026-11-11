import { GUARDS_METADATA } from '@nestjs/common/constants';

import { IS_PUBLIC_KEY } from '../../common/decorators/public.decorator';
import { KoreaderAuthGuard } from './koreader-auth.guard';
import { KoreaderFontController } from './koreader-font.controller';

describe('KoreaderFontController', () => {
  it('is public only for the global JWT guard and uses the KOReader auth guard', () => {
    expect(Reflect.getMetadata(IS_PUBLIC_KEY, KoreaderFontController)).toBe(true);
    expect(Reflect.getMetadata(GUARDS_METADATA, KoreaderFontController)).toEqual([KoreaderAuthGuard]);
  });

  it('forwards the list and file routes to the service', async () => {
    const fontService = {
      list: vi.fn().mockResolvedValue({ fonts: [] }),
      streamFile: vi.fn().mockResolvedValue(undefined),
    };
    const controller = new KoreaderFontController(fontService as never);
    const reply = { send: vi.fn() } as never;

    await expect(controller.list()).resolves.toEqual({ fonts: [] });
    await controller.file(12, reply);

    expect(fontService.list).toHaveBeenCalledTimes(1);
    expect(fontService.streamFile).toHaveBeenCalledWith(12, reply);
  });
});
