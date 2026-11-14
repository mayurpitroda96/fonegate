import { WebSocket } from 'ws';
import { db } from '../db';
import { Device, GatewayPacket, Message } from '../types';
import { WebhookService } from './webhook-service';
import { DashboardSocket } from '../ws/dashboard-socket';

export class DeviceManager {
  private static activeConnections = new Map<string, WebSocket>();
  private static disconnectTimers = new Map<string, NodeJS.Timeout>();

  public static registerConnection(deviceId: string, ws: WebSocket) {
    // Clear any pending disconnect grace timer if reconnected quickly
    const pendingTimer = this.disconnectTimers.get(deviceId);
    if (pendingTimer) {
      clearTimeout(pendingTimer);
      this.disconnectTimers.delete(deviceId);
      console.log(`Device reconnected within grace period: ${deviceId}`);
    }

    // Close stale connection if device reconnects before old socket's close event fires
    const oldWs = this.activeConnections.get(deviceId);
    if (oldWs && oldWs !== ws) {
      try {
        if (oldWs.readyState === WebSocket.OPEN || oldWs.readyState === WebSocket.CONNECTING) {
          oldWs.close(1000, 'Replaced by new connection');
        }
      } catch (_) {}
    }

    this.activeConnections.set(deviceId, ws);
    db.prepare(`
      UPDATE devices 
      SET is_online = 1, last_seen_at = ? 
      WHERE id = ?
    `).run(new Date().toISOString(), deviceId);

    const device = this.getDeviceById(deviceId);
    if (device) {
      DashboardSocket.broadcast('device:status', device);
    }
    console.log(`Device connected: ${deviceId}`);
  }

  public static removeConnection(deviceId: string, ws?: WebSocket) {
    // If a ws reference is given, only remove if it's still the current connection
    // This prevents a stale close event from removing a newer connection
    if (ws) {
      const currentWs = this.activeConnections.get(deviceId);
      if (currentWs && currentWs !== ws) return;
    }
    this.activeConnections.delete(deviceId);

    // Clear any existing timer
    const existingTimer = this.disconnectTimers.get(deviceId);
    if (existingTimer) {
      clearTimeout(existingTimer);
    }

    // 15-second grace period before marking offline
    const timer = setTimeout(() => {
      this.disconnectTimers.delete(deviceId);
      if (this.activeConnections.has(deviceId)) return;

      db.prepare(`
        UPDATE devices 
        SET is_online = 0, last_seen_at = ? 
        WHERE id = ?
      `).run(new Date().toISOString(), deviceId);

      const device = this.getDeviceById(deviceId);
      if (device) {
        DashboardSocket.broadcast('device:status', device);
      }
      console.log(`Device marked offline after grace period: ${deviceId}`);
    }, 15000);

    this.disconnectTimers.set(deviceId, timer);
    console.log(`Device socket closed, 15s reconnect grace period started: ${deviceId}`);
  }

  public static isOnline(deviceId: string): boolean {
    const ws = this.activeConnections.get(deviceId);
    return ws !== undefined && ws.readyState === WebSocket.OPEN;
  }

  public static getDeviceByToken(token: string): Device | null {
    const device = db.prepare('SELECT * FROM devices WHERE token = ?').get(token) as Device | undefined;
    return device || null;
  }

  public static getDeviceById(id: string): Device | null {
    const device = db.prepare('SELECT * FROM devices WHERE id = ?').get(id) as Device | undefined;
    return device || null;
  }

  public static getAnyOnlineDevice(): Device | null {
    for (const [id, ws] of this.activeConnections.entries()) {
      if (ws.readyState === WebSocket.OPEN) {
        return this.getDeviceById(id);
      }
    }
    return null;
  }

  public static sendToDevice(deviceId: string, packet: GatewayPacket): boolean {
    const ws = this.activeConnections.get(deviceId);
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      return false;
    }
    ws.send(JSON.stringify(packet));
    return true;
  }

  public static handleHeartbeat(
    deviceId: string,
    payload: {
      battery_level: number;
      is_charging: boolean;
      sim_info?: any;
      phone_number?: string;
    }
  ) {
    db.prepare(`
      UPDATE devices 
      SET battery_level = ?, is_charging = ?, sim_info = COALESCE(?, sim_info), 
          phone_number = COALESCE(?, phone_number), last_seen_at = ?, is_online = 1
      WHERE id = ?
    `).run(
      payload.battery_level ?? 100,
      payload.is_charging ? 1 : 0,
      payload.sim_info ? JSON.stringify(payload.sim_info) : null,
      payload.phone_number || null,
      new Date().toISOString(),
      deviceId
    );

    const updated = this.getDeviceById(deviceId);
    if (updated) {
      DashboardSocket.broadcast('device:status', updated);
    }
  }

  public static handleSmsStatusUpdate(
    messageId: string,
    status: 'sent' | 'delivered' | 'failed',
    error?: string
  ) {
    const now = new Date().toISOString();
    if (status === 'sent') {
      db.prepare(`
        UPDATE messages 
        SET status = 'sent', sent_at = ? 
        WHERE id = ?
      `).run(now, messageId);
    } else if (status === 'delivered') {
      db.prepare(`
        UPDATE messages 
        SET status = 'delivered', delivered_at = ? 
        WHERE id = ?
      `).run(now, messageId);
    } else if (status === 'failed') {
      db.prepare(`
        UPDATE messages 
        SET status = 'failed', error_message = ? 
        WHERE id = ?
      `).run(error || 'Failed to send on device', messageId);
    }

    const updatedMessage = db.prepare('SELECT * FROM messages WHERE id = ?').get(messageId) as Message | undefined;
    if (updatedMessage) {
      DashboardSocket.broadcast('sms:status', updatedMessage);
      WebhookService.dispatch(`sms.${status}`, updatedMessage);
    }
  }

  public static handleInboundSms(
    deviceId: string,
    payload: {
      id: string;
      phone_number: string;
      message: string;
      sim_slot?: number;
      received_at?: string;
    }
  ) {
    const now = payload.received_at || new Date().toISOString();
    db.prepare(`
      INSERT INTO messages (id, device_id, direction, phone_number, message, sim_slot, status, created_at, sent_at)
      VALUES (?, ?, 'inbound', ?, ?, ?, 'received', ?, ?)
    `).run(
      payload.id,
      deviceId,
      payload.phone_number,
      payload.message,
      payload.sim_slot ?? 0,
      now,
      now
    );

    const message = db.prepare('SELECT * FROM messages WHERE id = ?').get(payload.id) as Message;
    DashboardSocket.broadcast('sms:new', message);
    WebhookService.dispatch('sms.received', message);
  }
}

