import { Router, Response } from 'express';
import { db } from '../db';
import { authMiddleware, AuthenticatedRequest } from '../middleware/auth';

export const backupRouter = Router();

/**
 * GET /api/v1/backup/export
 * Exports all database records as a JSON backup
 */
backupRouter.get('/export', authMiddleware, (req: AuthenticatedRequest, res: Response) => {
  try {
    const devices = db.prepare('SELECT * FROM devices').all();
    const messages = db.prepare('SELECT * FROM messages').all();
    const webhooks = db.prepare('SELECT * FROM webhooks').all();

    const backup = {
      version: 1,
      exportedAt: new Date().toISOString(),
      counts: {
        devices: devices.length,
        messages: messages.length,
        webhooks: webhooks.length,
      },
      data: {
        devices,
        messages,
        webhooks,
      },
    };

    const filename = `opensms_backup_${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.json(backup);
  } catch (err: any) {
    res.status(500).json({ success: false, error: err.message || 'Export failed' });
  }
});

/**
 * POST /api/v1/backup/import
 * Imports database records from a JSON backup
 */
backupRouter.post('/import', authMiddleware, (req: AuthenticatedRequest, res: Response) => {
  try {
    const { mode = 'merge', data } = req.body;

    if (!data || typeof data !== 'object') {
      res.status(400).json({ success: false, error: 'Invalid backup format' });
      return;
    }

    const devices = Array.isArray(data.devices) ? data.devices : [];
    const messages = Array.isArray(data.messages) ? data.messages : [];
    const webhooks = Array.isArray(data.webhooks) ? data.webhooks : [];

    const runImport = db.transaction(() => {
      if (mode === 'replace') {
        db.prepare('DELETE FROM webhook_logs').run();
        db.prepare('DELETE FROM webhooks').run();
        db.prepare('DELETE FROM messages').run();
        db.prepare('DELETE FROM devices').run();
      }

      // Import devices
      const insertDevice = db.prepare(`
        INSERT OR REPLACE INTO devices (
          id, name, token, phone_number, sim_info, battery_level, 
          is_charging, is_online, last_seen_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      for (const d of devices) {
        if (!d.id || !d.token || !d.name) continue;
        insertDevice.run(
          d.id,
          d.name,
          d.token,
          d.phone_number || null,
          d.sim_info || null,
          d.battery_level ?? 100,
          d.is_charging ? 1 : 0,
          0, // online status reset on import
          d.last_seen_at || null,
          d.created_at || new Date().toISOString()
        );
      }

      // Import messages
      const insertMessage = db.prepare(`
        INSERT OR REPLACE INTO messages (
          id, device_id, direction, phone_number, message, sim_slot, 
          status, external_ref, error_message, sent_at, delivered_at, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `);

      for (const m of messages) {
        if (!m.id || !m.phone_number || !m.message) continue;
        insertMessage.run(
          m.id,
          m.device_id || null,
          m.direction || 'outbound',
          m.phone_number,
          m.message,
          m.sim_slot ?? 0,
          m.status || 'pending',
          m.external_ref || null,
          m.error_message || null,
          m.sent_at || null,
          m.delivered_at || null,
          m.created_at || new Date().toISOString()
        );
      }

      // Import webhooks
      const insertWebhook = db.prepare(`
        INSERT OR REPLACE INTO webhooks (id, url, secret, events, is_active, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `);

      for (const w of webhooks) {
        if (!w.id || !w.url || !w.secret) continue;
        insertWebhook.run(
          w.id,
          w.url,
          w.secret,
          typeof w.events === 'string' ? w.events : JSON.stringify(w.events || []),
          w.is_active ? 1 : 0,
          w.created_at || new Date().toISOString()
        );
      }
    });

    runImport();

    res.json({
      success: true,
      message: `Successfully imported ${devices.length} devices, ${messages.length} messages, and ${webhooks.length} webhooks.`,
      counts: {
        devices: devices.length,
        messages: messages.length,
        webhooks: webhooks.length,
      },
    });
  } catch (err: any) {
    res.status(500).json({ success: false, error: err.message || 'Import failed' });
  }
});

