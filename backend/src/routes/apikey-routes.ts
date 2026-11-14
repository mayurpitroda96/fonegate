import { Router, Response } from 'express';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../db';
import { authMiddleware, AuthenticatedRequest } from '../middleware/auth';

export const apiKeyRouter = Router();

apiKeyRouter.use(authMiddleware);

apiKeyRouter.get('/', (req: AuthenticatedRequest, res: Response) => {
  const rows = db.prepare('SELECT id, name, key, permissions, is_active, last_used_at, created_at FROM api_keys ORDER BY created_at DESC').all();
  res.json({ success: true, data: rows });
});

apiKeyRouter.post('/', (req: AuthenticatedRequest, res: Response) => {
  const { name, permissions } = req.body;
  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    res.status(400).json({ success: false, error: 'Name is required' });
    return;
  }

  const id = uuidv4();
  const key = `fg_${crypto.randomBytes(24).toString('hex')}`;
  const perms = JSON.stringify(permissions || ['sms:send', 'sms:read']);

  db.prepare(
    'INSERT INTO api_keys (id, name, key, permissions, is_active, created_at) VALUES (?, ?, ?, ?, 1, ?)'
  ).run(id, name.trim(), key, perms, new Date().toISOString());

  const created = db.prepare('SELECT * FROM api_keys WHERE id = ?').get(id);
  res.status(201).json({ success: true, data: created });
});

apiKeyRouter.delete('/:id', (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const result = db.prepare('DELETE FROM api_keys WHERE id = ?').run(id);
  if (result.changes === 0) {
    res.status(404).json({ success: false, error: 'API key not found' });
    return;
  }
  res.json({ success: true, message: 'API key deleted' });
});

apiKeyRouter.patch('/:id/toggle', (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const existing = db.prepare('SELECT is_active FROM api_keys WHERE id = ?').get(id) as any;
  if (!existing) {
    res.status(404).json({ success: false, error: 'API key not found' });
    return;
  }
  const newState = existing.is_active === 1 ? 0 : 1;
  db.prepare('UPDATE api_keys SET is_active = ? WHERE id = ?').run(newState, id);
  const updated = db.prepare('SELECT * FROM api_keys WHERE id = ?').get(id);
  res.json({ success: true, data: updated });
});
