import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { QueueService } from '../services/queue-service';
import { db } from '../db';

export const smsRouter = Router();

const sendSmsSchema = z.object({
  to: z.string().min(3, 'Phone number is required'),
  message: z.string().min(1, 'Message text cannot be empty'),
  deviceId: z.string().optional(),
  simSlot: z.number().int().min(0).max(1).optional().default(0),
  externalRef: z.string().optional(),
});

const sendBulkSmsSchema = z.object({
  messages: z.array(
    z.object({
      to: z.string().min(3),
      message: z.string().min(1),
      simSlot: z.number().int().min(0).max(1).optional().default(0),
      externalRef: z.string().optional(),
    })
  ).min(1, 'At least one message is required'),
  deviceId: z.string().optional(),
});

/**
 * POST /api/v1/sms/send
 */
smsRouter.post('/send', (req: Request, res: Response) => {
  try {
    const data = sendSmsSchema.parse(req.body);
    const queuedMessage = QueueService.enqueueSms({
      phoneNumber: data.to,
      message: data.message,
      deviceId: data.deviceId,
      simSlot: data.simSlot,
      externalRef: data.externalRef,
    });

    res.status(201).json({
      success: true,
      message: 'SMS queued successfully',
      data: queuedMessage,
    });
  } catch (err: any) {
    res.status(400).json({ success: false, error: err.message || err });
  }
});

/**
 * POST /api/v1/sms/send-bulk
 */
smsRouter.post('/send-bulk', (req: Request, res: Response) => {
  try {
    const data = sendBulkSmsSchema.parse(req.body);
    const results = data.messages.map((item) =>
      QueueService.enqueueSms({
        phoneNumber: item.to,
        message: item.message,
        deviceId: data.deviceId,
        simSlot: item.simSlot,
        externalRef: item.externalRef,
      })
    );

    res.status(201).json({
      success: true,
      count: results.length,
      data: results,
    });
  } catch (err: any) {
    res.status(400).json({ success: false, error: err.message || err });
  }
});

/**
 * GET /api/v1/sms/messages
 */
smsRouter.get('/messages', (req: Request, res: Response) => {
  try {
    const page = parseInt(req.query.page as string || '1', 10);
    const limit = Math.min(parseInt(req.query.limit as string || '50', 10), 100);
    const offset = (page - 1) * limit;

    const status = req.query.status as string | undefined;
    const direction = req.query.direction as string | undefined;
    const search = req.query.search as string | undefined;

    let query = 'SELECT * FROM messages WHERE 1=1';
    const params: any[] = [];

    if (status) {
      query += ' AND status = ?';
      params.push(status);
    }
    if (direction) {
      query += ' AND direction = ?';
      params.push(direction);
    }
    if (search) {
      query += ' AND (phone_number LIKE ? OR message LIKE ?)';
      params.push(`%${search}%`, `%${search}%`);
    }

    const countQuery = query.replace('SELECT *', 'SELECT COUNT(*) as total');
    const totalRow = db.prepare(countQuery).get(...params) as { total: number };

    query += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);

    const rows = db.prepare(query).all(...params);

    res.json({
      success: true,
      pagination: {
        page,
        limit,
        total: totalRow.total,
        totalPages: Math.ceil(totalRow.total / limit),
      },
      data: rows,
    });
  } catch (err: any) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/sms/messages/:id
 */
smsRouter.get('/messages/:id', (req: Request, res: Response) => {
  const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const message = db.prepare('SELECT * FROM messages WHERE id = ?').get(id);
  if (!message) {
    res.status(404).json({ success: false, error: 'Message not found' });
    return;
  }
  res.json({ success: true, data: message });
});

/**
 * POST /api/v1/sms/messages/:id/retry
 */
smsRouter.post('/messages/:id/retry', (req: Request, res: Response) => {
  const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  const retried = QueueService.retryMessage(id);
  if (!retried) {
    res.status(404).json({ success: false, error: 'Message not found' });
    return;
  }
  res.json({ success: true, message: 'Message re-queued', data: retried });
});

/**
 * DELETE /api/v1/sms/messages/:id
 */
smsRouter.delete('/messages/:id', (req: Request, res: Response) => {
  const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
  db.prepare('DELETE FROM messages WHERE id = ?').run(id);
  res.json({ success: true, message: 'Message deleted' });
});
