import { Router, Response } from 'express';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { z } from 'zod';
import { db, hashPassword } from '../db';
import { config } from '../config';
import { authMiddleware, AuthenticatedRequest } from '../middleware/auth';

export const authRouter = Router();

const loginSchema = z.object({
  username: z.string().min(1, 'Username is required'),
  password: z.string().min(1, 'Password is required'),
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Current password is required'),
  newPassword: z.string().min(6, 'New password must be at least 6 characters'),
});

/**
 * POST /api/v1/auth/login
 */
authRouter.post('/login', (req, res: Response) => {
  try {
    const { username, password } = loginSchema.parse(req.body);
    const user = db.prepare('SELECT * FROM admin_users WHERE username = ?').get(username) as any;

    if (!user) {
      res.status(401).json({ success: false, error: 'Invalid username or password' });
      return;
    }

    const calculatedHash = hashPassword(password, user.salt);
    if (calculatedHash !== user.password_hash) {
      res.status(401).json({ success: false, error: 'Invalid username or password' });
      return;
    }

    const token = jwt.sign(
      { id: user.id, username: user.username },
      config.jwtSecret,
      { expiresIn: '7d' }
    );

    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        username: user.username,
      },
    });
  } catch (err: any) {
    res.status(400).json({ success: false, error: err.message || 'Login failed' });
  }
});

/**
 * GET /api/v1/auth/me
 */
authRouter.get('/me', authMiddleware, (req: AuthenticatedRequest, res: Response) => {
  res.json({ success: true, user: req.user });
});

/**
 * POST /api/v1/auth/change-password
 */
authRouter.post('/change-password', authMiddleware, (req: AuthenticatedRequest, res: Response) => {
  try {
    const { currentPassword, newPassword } = changePasswordSchema.parse(req.body);
    const userId = req.user?.id;

    const user = db.prepare('SELECT * FROM admin_users WHERE id = ?').get(userId) as any;
    if (!user) {
      res.status(404).json({ success: false, error: 'User not found' });
      return;
    }

    if (hashPassword(currentPassword, user.salt) !== user.password_hash) {
      res.status(400).json({ success: false, error: 'Current password does not match' });
      return;
    }

    const newSalt = crypto.randomBytes(16).toString('hex');
    const newHash = hashPassword(newPassword, newSalt);

    db.prepare('UPDATE admin_users SET password_hash = ?, salt = ? WHERE id = ?').run(
      newHash,
      newSalt,
      userId
    );

    res.json({ success: true, message: 'Password updated successfully' });
  } catch (err: any) {
    res.status(400).json({ success: false, error: err.message || 'Password change failed' });
  }
});

