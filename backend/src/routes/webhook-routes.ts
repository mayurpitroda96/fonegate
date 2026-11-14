import { Router, Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import crypto from 'crypto';
import { z } from 'zod';
import { db } from '../db';
import { WebhookService } from '../services/webhook-service';

export const webhookRouter = Router();

const createWebhookSchema = z.object({
  url: z.string().url('Must be a valid HTTP or HTTPS URL'),
  events: z.array(z.string()).min(1, 'Select at least one event'),
  secret: z.string().optional(),
});

/**
 * GET /api/v1/webhooks
 */
webhookRouter.get('/', (req: Request, res: Response) => {
  const webhooks = db.prepare('SELECT * FROM webhooks ORDER BY created_at DESC').all();
  res.json({ success: true, data: webhooks });
});

/**
 * POST /api/v1/webhooks
 */
webhookRouter.post('/', (req: Request, res: Response) => {
  try {
    const data = createWebhookSchema.parse(req.body);
    const id = uuidv4();
    const secret = data.secret || crypto.randomBytes(24).toString('hex');
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO webhooks (id, url, secret, events, is_active, created_at)
      VALUES (?, ?, ?, ?, 1, ?)
    `).run(id, data.url, secret, JSON.stringify(data.events), now);

    const created = db.prepare('SELECT * FROM webhooks WHERE id = ?').get(id);
    res.status(201).json({ success: true, data: created });
  } catch (err: any) {
    res.status(400).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/webhooks/:id/test
 * Dispatches a simulated test event
 */
webhookRouter.post('/:id/test', async (req: Request, res: Response) => {
  const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const webhook = db.prepare('SELECT * FROM webhooks WHERE id = ?').get(id);
  if (!webhook) {
    res.status(404).json({ success: false, error: 'Webhook not found' });
    return;
  }

  await WebhookService.dispatch('webhook.test', {
    test: true,
    message: 'Hello from FoneGate Webhook Dispatcher!',
    time: new Date().toISOString(),
  });

  res.json({ success: true, message: 'Test webhook event dispatched' });
});

/**
 * DELETE /api/v1/webhooks/:id
 */
webhookRouter.delete('/:id', (req: Request, res: Response) => {
  const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  db.prepare('DELETE FROM webhooks WHERE id = ?').run(id);
  res.json({ success: true, message: 'Webhook deleted' });
});

/**
 * GET /api/v1/webhooks/logs
 */
webhookRouter.get('/logs', (req: Request, res: Response) => {
  const limit = Math.min(parseInt(req.query.limit as string || '50', 10), 100);
  const logs = db.prepare(`
    SELECT l.*, w.url 
    FROM webhook_logs l 
    JOIN webhooks w ON l.webhook_id = w.id 
    ORDER BY l.created_at DESC 
    LIMIT ?
  `).all(limit);
  res.json({ success: true, data: logs });
});
