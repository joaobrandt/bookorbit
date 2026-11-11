import type { UserFont } from '@bookorbit/types';

import { KoreaderFontService } from './koreader-font.service';

vi.mock('fs', () => ({
  createReadStream: vi.fn(() => 'mock-stream'),
}));

function makeFont(overrides: Partial<UserFont> = {}): UserFont {
  return {
    id: 1,
    familyName: 'Literata',
    originalFileName: 'Literata-Regular.ttf',
    format: 'ttf',
    weight: 400,
    style: 'normal',
    weightMin: null,
    weightMax: null,
    instances: null,
    fileSize: 1200,
    createdAt: '2026-11-01T00:00:00.000Z',
    ...overrides,
  };
}

function makeService() {
  const serverFonts = {
    list: vi.fn().mockResolvedValue([]),
    getFileInfo: vi.fn(),
  };
  const service = new KoreaderFontService(serverFonts as never);
  return { service, serverFonts };
}

describe('KoreaderFontService', () => {
  describe('list', () => {
    it('returns only the fields a device needs to keep a copy', async () => {
      const { service, serverFonts } = makeService();
      serverFonts.list.mockResolvedValue([makeFont({ id: 3, format: 'woff2', fileSize: 980 }), makeFont({ id: 5, format: 'otf', fileSize: 42 })]);

      await expect(service.list()).resolves.toEqual({
        fonts: [
          { id: 3, format: 'woff2', fileSize: 980 },
          { id: 5, format: 'otf', fileSize: 42 },
        ],
      });
    });
  });

  describe('streamFile', () => {
    it('streams the stored file with its font media type', async () => {
      const { service, serverFonts } = makeService();
      serverFonts.getFileInfo.mockResolvedValue({ filePath: '/data/fonts/a.otf', font: { format: 'otf' } });
      const reply = { header: vi.fn().mockReturnThis(), send: vi.fn() };

      await service.streamFile(4, reply as never);

      expect(serverFonts.getFileInfo).toHaveBeenCalledWith(4);
      expect(reply.header).toHaveBeenCalledWith('Content-Type', 'font/otf');
      expect(reply.send).toHaveBeenCalledWith('mock-stream');
    });
  });
});
