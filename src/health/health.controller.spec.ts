import { HealthController } from './health.controller.js';

describe('HealthController', () => {
  it('retorna o estado saudavel da API', () => {
    const controller = new HealthController();

    expect(controller.getHealth()).toEqual({
      status: 'ok',
      service: 'bookmatch-backend',
      timestamp: expect.any(String),
    });
  });
});
