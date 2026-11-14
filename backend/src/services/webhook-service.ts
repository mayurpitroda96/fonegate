import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../db';
import { Webhook } from '../types';
import { config } from '../config';

export class WebhookService {
  /**
   * Dispatches an event to all active webhooks subscribed to that event.
   */
  public static async dispatch(event: string, data: any) {
    try {
      const activeWebhooks = db
        .prepare('SELECT * FROM webhooks WHERE is_active = 1')
        .all() as Webhook[];

      const payloadString = JSON.stringify({
        event,
        timestamp: new Date().toISOString(),
        data,
      });

      for (const webhook of activeWebhooks) {
        let subscribedEvents: string[] = [];
        try {
          subscribedEvents = JSON.parse(webhook.events);
        } catch {
          subscribedEvents = [];
        }

        if (subscribedEvents.includes(event) || subscribedEvents.includes('*')) {
          this.sendWebhook(webhook, event, payloadString);
        }
      }
    } catch (err) {
      console.error('Error dispatching webhooks:', err);
    }
  }

  private static async sendWebhook(webhook: Webhook, event: string, payload: string) {
    const logId = uuidv4();
    const startTime = Date.now();
    let responseStatus: number | null = null;
    let errorMessage: string | null = null;

    try {
      const signature = crypto
        .createHmac('sha256', webhook.secret)
        .update(payload)
        .digest('hex');

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), config.webhookTimeoutMs);

      const response = await fetch(webhook.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-SMS-Signature': signature,
          'X-SMS-Event': event,
          'User-Agent': 'FoneGate/1.0',
        },
        body: payload,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);
      responseStatus = response.status;
    } catch (err: any) {
      errorMessage = err.message || 'Unknown network error';
    } finally {
      const durationMs = Date.now() - startTime;
      db.prepare(`
        INSERT INTO webhook_logs (id, webhook_id, event, payload, response_status, error, duration_ms, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        logId,
        webhook.id,
        event,
        payload,
        responseStatus,
        errorMessage,
        durationMs,
        new Date().toISOString()
      );
    }
  }
}

