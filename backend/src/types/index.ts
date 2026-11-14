export type MessageDirection = 'inbound' | 'outbound';
export type MessageStatus = 'pending' | 'queued' | 'sent' | 'delivered' | 'failed' | 'received';

export interface Device {
  id: string;
  name: string;
  token: string;
  phone_number: string | null;
  sim_info: string | null; // JSON string with slot info
  battery_level: number;
  is_charging: boolean;
  is_online: boolean;
  last_seen_at: string | null;
  created_at: string;
}

export interface Message {
  id: string;
  device_id: string | null;
  direction: MessageDirection;
  phone_number: string;
  message: string;
  sim_slot: number; // 0 for SIM 1, 1 for SIM 2
  status: MessageStatus;
  external_ref: string | null;
  error_message: string | null;
  sent_at: string | null;
  delivered_at: string | null;
  created_at: string;
}

export interface Webhook {
  id: string;
  url: string;
  secret: string;
  events: string; // JSON array of event names
  is_active: boolean;
  created_at: string;
}

export interface WebhookLog {
  id: string;
  webhook_id: string;
  event: string;
  payload: string;
  response_status: number | null;
  error: string | null;
  duration_ms: number;
  created_at: string;
}

// WebSocket Packet Types
export type GatewayPacketType =
  | 'AUTH'
  | 'AUTH_SUCCESS'
  | 'AUTH_FAILED'
  | 'HEARTBEAT'
  | 'SEND_SMS'
  | 'SMS_SENT'
  | 'SMS_DELIVERED'
  | 'SMS_FAILED'
  | 'SMS_RECEIVED'
  | 'PING';

export interface GatewayPacket {
  type: GatewayPacketType;
  id?: string;
  payload: any;
}

