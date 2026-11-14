import { WebSocket } from 'ws';
import { DeviceManager } from '../services/device-manager';
import { QueueService } from '../services/queue-service';
import { GatewayPacket } from '../types';

export function handleGatewayConnection(ws: WebSocket) {
  let authenticatedDeviceId: string | null = null;
  let missedPongs = 0;

  // Server-side ping to detect dead connections.
  // OEM systems (Transsion USF) freeze app processes but unfreeze on incoming packets.
  // Frequent pings keep the TCP connection alive and trigger unfreezes.
  // Allow 8 missed pongs (8 × 15s = 120s) before terminating.
  const pingInterval = setInterval(() => {
    if (missedPongs >= 8) {
      clearInterval(pingInterval);
      ws.terminate();
      return;
    }
    missedPongs++;
    ws.ping();
  }, 15000);

  ws.on('pong', () => {
    missedPongs = 0;
  });

  // Set timeout to force auth within 10 seconds
  const authTimeout = setTimeout(() => {
    if (!authenticatedDeviceId) {
      ws.send(JSON.stringify({ type: 'AUTH_FAILED', payload: { error: 'Authentication timeout' } }));
      ws.close();
    }
  }, 10000);

  ws.on('message', (data: Buffer | string) => {
    try {
      const packet: GatewayPacket = JSON.parse(data.toString());

      if (packet.type === 'AUTH') {
        const token = packet.payload?.token;
        if (!token) {
          ws.send(JSON.stringify({ type: 'AUTH_FAILED', payload: { error: 'Missing token' } }));
          ws.close();
          return;
        }

        const device = DeviceManager.getDeviceByToken(token);
        if (!device) {
          ws.send(JSON.stringify({ type: 'AUTH_FAILED', payload: { error: 'Invalid device token' } }));
          ws.close();
          return;
        }

        clearTimeout(authTimeout);
        authenticatedDeviceId = device.id;
        DeviceManager.registerConnection(device.id, ws);

        ws.send(JSON.stringify({
          type: 'AUTH_SUCCESS',
          payload: { device_id: device.id, name: device.name },
        }));

        // Flush any pending queue to this device
        QueueService.processPendingQueue(device.id);
        return;
      }

      // Remaining packet types require authentication
      if (!authenticatedDeviceId) {
        ws.send(JSON.stringify({ type: 'AUTH_FAILED', payload: { error: 'Unauthorized' } }));
        ws.close();
        return;
      }

      switch (packet.type) {
        case 'HEARTBEAT':
          DeviceManager.handleHeartbeat(authenticatedDeviceId, packet.payload);
          break;

        case 'SMS_SENT':
          DeviceManager.handleSmsStatusUpdate(packet.payload.id, 'sent');
          break;

        case 'SMS_DELIVERED':
          DeviceManager.handleSmsStatusUpdate(packet.payload.id, 'delivered');
          break;

        case 'SMS_FAILED':
          DeviceManager.handleSmsStatusUpdate(packet.payload.id, 'failed', packet.payload.error);
          break;

        case 'SMS_RECEIVED':
          DeviceManager.handleInboundSms(authenticatedDeviceId, packet.payload);
          break;

        case 'PING':
          break;

        default:
          console.warn(`Unknown packet type: ${packet.type}`);
      }
    } catch (err) {
      console.error('Error parsing gateway packet:', err);
    }
  });

  ws.on('close', () => {
    clearInterval(pingInterval);
    clearTimeout(authTimeout);
    if (authenticatedDeviceId) {
      DeviceManager.removeConnection(authenticatedDeviceId, ws);
    }
  });

  ws.on('error', (err) => {
    clearInterval(pingInterval);
    console.error('Gateway socket error:', err);
  });
}

