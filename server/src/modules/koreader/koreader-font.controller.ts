import { Controller, Get, Header, Param, ParseIntPipe, Res, UseGuards } from '@nestjs/common';
import type { FastifyReply } from 'fastify';

import { Public } from '../../common/decorators/public.decorator';
import { KoreaderAuthGuard } from './koreader-auth.guard';
import { KoreaderFontService } from './koreader-font.service';

@Public()
@UseGuards(KoreaderAuthGuard)
@Controller('koreader/plugin/fonts')
export class KoreaderFontController {
  constructor(private readonly fontService: KoreaderFontService) {}

  @Get()
  @Header('Cache-Control', 'no-store')
  list() {
    return this.fontService.list();
  }

  @Get(':fontId/file')
  file(@Param('fontId', ParseIntPipe) fontId: number, @Res() reply: FastifyReply) {
    return this.fontService.streamFile(fontId, reply);
  }
}
