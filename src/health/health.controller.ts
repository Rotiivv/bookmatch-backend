import { Controller, Get } from '@nestjs/common';
import { ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';

export interface HealthResponse {
  status: 'ok';
  service: 'bookmatch-backend';
  timestamp: string;
}

@ApiTags('health')
@Controller('health')
export class HealthController {
  @Get()
  @ApiOperation({ summary: 'Verifica se a API esta disponivel' })
  @ApiOkResponse({
    description: 'API disponivel',
    schema: {
      example: {
        status: 'ok',
        service: 'bookmatch-backend',
        timestamp: '2026-11-05T12:00:00.000Z',
      },
    },
  })
  getHealth(): HealthResponse {
    return {
      status: 'ok',
      service: 'bookmatch-backend',
      timestamp: new Date().toISOString(),
    };
  }
}
