import Database from 'better-sqlite3';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { config } from '../config';

const dbDir = path.dirname(config.dbPath);
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

export const db = new Database(config.dbPath);

// Enable WAL mode for high concurrency
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

export function hashPassword(password: string, salt: string): string {
  return crypto.scryptSync(password, salt, 64).toString('hex');
}

export function initDatabase() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS admin_users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS devices (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      token TEXT UNIQUE NOT NULL,
      phone_number TEXT,
      sim_info TEXT,
      battery_level INTEGER DEFAULT 100,
      is_charging INTEGER DEFAULT 0,
      is_online INTEGER DEFAULT 0,
      last_seen_at TEXT,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      device_id TEXT,
      direction TEXT NOT NULL,
      phone_number TEXT NOT NULL,
      message TEXT NOT NULL,
      sim_slot INTEGER DEFAULT 0,
      status TEXT NOT NULL,
      external_ref TEXT,
      error_message TEXT,
      sent_at TEXT,
      delivered_at TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL
    );

    CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status);
    CREATE INDEX IF NOT EXISTS idx_messages_direction ON messages(direction);
    CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);

    CREATE TABLE IF NOT EXISTS webhooks (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      secret TEXT NOT NULL,
      events TEXT NOT NULL,
      is_active INTEGER DEFAULT 1,
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS webhook_logs (
      id TEXT PRIMARY KEY,
      webhook_id TEXT NOT NULL,
      event TEXT NOT NULL,
      payload TEXT NOT NULL,
      response_status INTEGER,
      error TEXT,
      duration_ms INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (webhook_id) REFERENCES webhooks(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS api_keys (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      key TEXT UNIQUE NOT NULL,
      permissions TEXT NOT NULL DEFAULT '["sms:send","sms:read"]',
      is_active INTEGER DEFAULT 1,
      last_used_at TEXT,
      created_at TEXT NOT NULL
    );
  `);

  // Ensure default admin exists
  const adminCount = (db.prepare('SELECT COUNT(*) as count FROM admin_users').get() as { count: number }).count;
  if (adminCount === 0) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hash = hashPassword('admin123', salt);
    db.prepare(`
      INSERT INTO admin_users (id, username, password_hash, salt, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(uuidv4(), 'admin', hash, salt, new Date().toISOString());
    console.log('Default admin created -> Username: admin | Password: admin123');
  }

  // Ensure any devices marked online previously are marked offline until reconnected
  db.prepare('UPDATE devices SET is_online = 0').run();
  console.log('Database initialized successfully with SQLite at:', config.dbPath);
}

