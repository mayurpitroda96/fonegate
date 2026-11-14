import { Router, Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { z } from 'zod';
import { db } from '../db';

export const deviceRouter = Router();

const createDeviceSchema = z.object({
  name: z.string().min(1, 'Device name is required'),
});

/**
 * GET /api/v1/devices
 */
deviceRouter.get('/', (req: Request, res: Response) => {
  const devices = db.prepare('SELECT * FROM devices ORDER BY created_at DESC').all();
  res.json({ success: true, data: devices });
});

/**
 * POST /api/v1/devices
 * Registers a new device and returns the device token for pairing
 */
deviceRouter.post('/', (req: Request, res: Response) => {
  try {
    const data = createDeviceSchema.parse(req.body);
    const id = uuidv4();
    const token = 'gw_' + uuidv4().replace(/-/g, '');
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO devices (id, name, token, created_at)
      VALUES (?, ?, ?, ?)
    `).run(id, data.name, token, now);

    const created = db.prepare('SELECT * FROM devices WHERE id = ?').get(id);

    res.status(201).json({
      success: true,
      data: created,
    });
  } catch (err: any) {
    res.status(400).json({ success: false, error: err.message });
  }
});

/**
 * DELETE /api/v1/devices/:id
 */
deviceRouter.delete('/:id', (req: Request, res: Response) => {
  const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  db.prepare('DELETE FROM devices WHERE id = ?').run(id);
  res.json({ success: true, message: 'Device removed successfully' });
});
