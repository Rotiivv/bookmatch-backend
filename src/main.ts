import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NestNodeApplication, NodeAdapter } from '@nestjs/platform-node';
import { AppModule } from './app.module.js';
import { configureApp } from './configure-app.js';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestNodeApplication>(
    AppModule,
    new NodeAdapter(),
  );

  configureApp(app);

  await app.listen(process.env.PORT ?? 3000);
}

await bootstrap();
