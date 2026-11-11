import { Injectable } from '@nestjs/common';
import type { FastifyReply } from 'fastify';
import { createReadStream } from 'fs';

import { FONT_FORMAT_MIME_TYPES, type KoreaderServerFontList } from '@bookorbit/types';
import { ServerFontService } from '../server-font/server-font.service';

/**
 * The administrator's font collection as a KOReader device copies it. The list is bounded by
 * MAX_SERVER_FONTS, so it is returned whole.
 */
@Injectable()
export class KoreaderFontService {
  constructor(private readonly serverFonts: ServerFontService) {}

  async list(): Promise<KoreaderServerFontList> {
    const fonts = await this.serverFonts.list();
    return { fonts: fonts.map(({ id, format, fileSize }) => ({ id, format, fileSize })) };
  }

  async streamFile(fontId: number, reply: FastifyReply): Promise<void> {
    const { filePath, font } = await this.serverFonts.getFileInfo(fontId);
    reply.header('Content-Type', FONT_FORMAT_MIME_TYPES[font.format]);
    reply.header('Cache-Control', 'no-store');
    reply.send(createReadStream(filePath));
  }
}
