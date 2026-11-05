import type { RequestListener, ServerResponse } from 'node:http';
import type { NestNodeApplication } from '@nestjs/platform-node';
import { NodeAdapter } from '@nestjs/platform-node';
import { Test, type TestingModule } from '@nestjs/testing';
import { inject } from 'light-my-request';
import { AppModule } from '../src/app.module.js';
import { configureApp } from '../src/configure-app.js';

const injectionResponseMethods = [
  'setTimeout',
  'writeHead',
  'write',
  'end',
  'destroy',
  'addTrailers',
] as const;

function preserveInjectionResponseMethods(response: ServerResponse): void {
  for (const methodName of injectionResponseMethods) {
    const method = response[methodName] as (...args: unknown[]) => unknown;

    Object.defineProperty(response, methodName, {
      configurable: true,
      value: method.bind(response),
    });
  }
}

function createInjectionDispatch(app: NestNodeApplication): RequestListener {
  const router = app.getHttpAdapter().getInstance();

  return (request, response) => {
    // NodeRouter aplica NodeResponse ao prototipo. Mantemos como metodos
    // proprios os coletores de resposta do injetor HTTP sem socket.
    preserveInjectionResponseMethods(response);
    router(request, response);
  };
}

describe('Health (e2e)', () => {
  let app: NestNodeApplication;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication<NestNodeApplication>(
      new NodeAdapter(),
    );
    configureApp(app);
    await app.init();
  });

  afterEach(async () => {
    await app.close();
  });

  it('GET /health', async () => {
    const response = await inject(createInjectionDispatch(app), {
      method: 'GET',
      url: '/health',
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      status: 'ok',
      service: 'bookmatch-backend',
      timestamp: expect.any(String),
    });
  });

  it('GET /api/docs', async () => {
    const response = await inject(createInjectionDispatch(app), {
      method: 'GET',
      url: '/api/docs',
    });

    expect(response.statusCode).toBe(200);
    expect(response.payload).toContain('Swagger UI');
  });
});
