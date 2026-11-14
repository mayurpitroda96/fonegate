import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { db } from '../db';

export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    username: string;
  };
  apiKeyId?: string;
}

export function authMiddleware(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1];
    try {
      const decoded = jwt.verify(token, config.jwtSecret) as { id: string; username: string };
      req.user = decoded;
      return next();
    } catch (err) {
      res.status(401).json({ success: false, error: 'Unauthorized: Invalid or expired token' });
      return;
    }
  }

  res.status(401).json({ success: false, error: 'Unauthorized: Missing or invalid token' });
}

export function apiKeyOrAuthMiddleware(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const apiKeyHeader = req.headers['x-api-key'] as string | undefined;
  if (apiKeyHeader) {
    const row = db.prepare('SELECT id, is_active FROM api_keys WHERE key = ?').get(apiKeyHeader) as any;
    if (row && row.is_active === 1) {
      req.user = { id: 'apikey_' + row.id, username: 'api_key' };
      req.apiKeyId = row.id;
      db.prepare('UPDATE api_keys SET last_used_at = ? WHERE id = ?').run(new Date().toISOString(), row.id);
      return next();
    }
    res.status(401).json({ success: false, error: 'Unauthorized: Invalid or inactive API key' });
    return;
  }

  authMiddleware(req, res, next);
}
