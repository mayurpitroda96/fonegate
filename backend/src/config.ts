import dotenv from 'dotenv';
import path from 'path';

dotenv.config();

export const config = {
  port: parseInt(process.env.PORT || '8080', 10),
  host: process.env.HOST || '0.0.0.0',
  dbPath: process.env.DB_PATH || path.join(process.cwd(), 'data', 'sms_gateway.db'),
  apiKey: process.env.API_KEY || 'default-secret-api-key',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  webhookTimeoutMs: parseInt(process.env.WEBHOOK_TIMEOUT_MS || '5000', 10),
  jwtSecret: process.env.JWT_SECRET || 'fonegate-super-secret-jwt-key-2026',
};

