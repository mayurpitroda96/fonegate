import { v4 as uuidv4 } from 'uuid';
import { db } from '../db';
import { Message } from '../types';
import { DeviceManager } from './device-manager';
import { DashboardSocket } from '../ws/dashboard-socket';

export class QueueService {
  /**
   * Enqueues an SMS to be sent via an Android gateway device.
   */
  public static enqueueSms(options: {
    phoneNumber: string;
    message: string;
    deviceId?: string;
    simSlot?: number;
    externalRef?: string;
  }): Message {
    const id = uuidv4();
    const now = new Date().toISOString();
    const simSlot = options.simSlot ?? 0;

    let targetDevice = options.deviceId
      ? DeviceManager.getDeviceById(options.deviceId)
      : DeviceManager.getAnyOnlineDevice();

    const isTargetOnline = targetDevice && DeviceManager.isOnline(targetDevice.id);
    const initialStatus = isTargetOnline ? 'queued' : 'pending';

    db.prepare(`
      INSERT INTO messages (
        id, device_id, direction, phone_number, message, sim_slot, 
        status, external_ref, created_at
      ) VALUES (?, ?, 'outbound', ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      targetDevice ? targetDevice.id : null,
      options.phoneNumber,
      options.message,
      simSlot,
      initialStatus,
      options.externalRef || null,
      now
    );

    const message = db.prepare('SELECT * FROM messages WHERE id = ?').get(id) as Message;
    DashboardSocket.broadcast('sms:new', message);

    if (isTargetOnline && targetDevice) {
      this.dispatchToDevice(targetDevice.id, message);
    }

    return message;
  }

  /**
   * Dispatches a specific message to an online device via WebSocket.
   */
  public static dispatchToDevice(deviceId: string, message: Message): boolean {
    const sent = DeviceManager.sendToDevice(deviceId, {
      type: 'SEND_SMS',
      id: message.id,
      payload: {
        id: message.id,
        phone_number: message.phone_number,
        message: message.message,
        sim_slot: message.sim_slot,
      },
    });

    if (sent) {
      db.prepare(`
        UPDATE messages 
        SET status = 'queued', device_id = ? 
        WHERE id = ?
      `).run(deviceId, message.id);
    }

    return sent;
  }

  /**
   * Process all pending messages when a device comes online.
   */
  public static processPendingQueue(deviceId: string) {
    const pending = db.prepare(`
      SELECT * FROM messages 
      WHERE status = 'pending' AND (device_id = ? OR device_id IS NULL)
      ORDER BY created_at ASC 
      LIMIT 20
    `).all(deviceId) as Message[];

    for (const msg of pending) {
      this.dispatchToDevice(deviceId, msg);
    }
  }

  /**
   * Retry a failed message.
   */
  public static retryMessage(messageId: string): Message | null {
    const msg = db.prepare('SELECT * FROM messages WHERE id = ?').get(messageId) as Message | undefined;
    if (!msg) return null;

    const targetDevice = msg.device_id
      ? DeviceManager.getDeviceById(msg.device_id)
      : DeviceManager.getAnyOnlineDevice();

    const isOnline = targetDevice && DeviceManager.isOnline(targetDevice.id);

    db.prepare(`
      UPDATE messages 
      SET status = ?, error_message = NULL 
      WHERE id = ?
    `).run(isOnline ? 'queued' : 'pending', messageId);

    const updated = db.prepare('SELECT * FROM messages WHERE id = ?').get(messageId) as Message;
    DashboardSocket.broadcast('sms:status', updated);

    if (isOnline && targetDevice) {
      this.dispatchToDevice(targetDevice.id, updated);
    }

    return updated;
  }
}

