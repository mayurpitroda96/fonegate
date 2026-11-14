import { Router, Request, Response } from 'express';
import { db } from '../db';

export const statsRouter = Router();

/**
 * GET /api/v1/stats
 */
statsRouter.get('/', (req: Request, res: Response) => {
  const totalSent = (db.prepare("SELECT COUNT(*) as count FROM messages WHERE direction = 'outbound' AND status IN ('sent', 'delivered')").get() as any).count;
  const totalDelivered = (db.prepare("SELECT COUNT(*) as count FROM messages WHERE status = 'delivered'").get() as any).count;
  const totalFailed = (db.prepare("SELECT COUNT(*) as count FROM messages WHERE status = 'failed'").get() as any).count;
  const totalReceived = (db.prepare("SELECT COUNT(*) as count FROM messages WHERE direction = 'inbound'").get() as any).count;
  const pendingQueue = (db.prepare("SELECT COUNT(*) as count FROM messages WHERE status IN ('pending', 'queued')").get() as any).count;
  const activeDevices = (db.prepare("SELECT COUNT(*) as count FROM devices WHERE is_online = 1").get() as any).count;
  const totalDevices = (db.prepare("SELECT COUNT(*) as count FROM devices").get() as any).count;

  res.json({
    success: true,
    data: {
      totalSent,
      totalDelivered,
      totalFailed,
      totalReceived,
      pendingQueue,
      activeDevices,
      totalDevices,
    },
  });
});

