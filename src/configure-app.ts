import { ValidationPipe } from '@nestjs/common';
import type { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

export function configureApp(app: INestApplication): void {
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const swaggerConfig = new DocumentBuilder()
    .setTitle('BookMatch API')
    .setDescription('API REST da plataforma BookMatch')
    .setVersion('0.0.1')
    .build();

  const documentFactory = () =>
    SwaggerModule.createDocument(app, swaggerConfig);

  SwaggerModule.setup('api/docs', app, documentFactory);
}
