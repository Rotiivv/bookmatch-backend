import 'dotenv/config';
import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { PrismaMariaDb } from '@prisma/adapter-mariadb';
import { PrismaClient } from '../generated/prisma/client.js';

function createAdapter(): PrismaMariaDb {
  return new PrismaMariaDb({
    host: process.env.DATABASE_HOST ?? 'localhost',
    port: Number(process.env.DATABASE_PORT ?? 3306),
    user: process.env.DATABASE_USER ?? 'bookmatch',
    password: process.env.DATABASE_PASSWORD ?? 'bookmatch_dev',
    database: process.env.DATABASE_NAME ?? 'bookmatch',
    connectionLimit: 5,
  });
}

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleDestroy {
  constructor() {
    super({ adapter: createAdapter() });
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
