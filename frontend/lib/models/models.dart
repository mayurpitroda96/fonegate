import 'dart:convert';

class Device {
  final String id;
  final String name;
  final String token;
  final String? phoneNumber;
  final String? simInfo;
  final int batteryLevel;
  final bool isCharging;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  Device({
    required this.id,
    required this.name,
    required this.token,
    this.phoneNumber,
    this.simInfo,
    required this.batteryLevel,
    required this.isCharging,
    required this.isOnline,
    this.lastSeenAt,
    required this.createdAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      token: json['token'] as String,
      phoneNumber: json['phone_number'] as String?,
      simInfo: json['sim_info'] as String?,
      batteryLevel: json['battery_level'] as int? ?? 100,
      isCharging: (json['is_charging'] as int? ?? 0) == 1,
      isOnline: (json['is_online'] as int? ?? 0) == 1,
      lastSeenAt: json['last_seen_at'] != null ? DateTime.parse(json['last_seen_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SmsMessage {
  final String id;
  final String? deviceId;
  final String direction; // 'inbound' | 'outbound'
  final String phoneNumber;
  final String message;
  final int simSlot;
  final String status; // 'pending' | 'queued' | 'sent' | 'delivered' | 'failed' | 'received'
  final String? externalRef;
  final String? errorMessage;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;

  SmsMessage({
    required this.id,
    this.deviceId,
    required this.direction,
    required this.phoneNumber,
    required this.message,
    required this.simSlot,
    required this.status,
    this.externalRef,
    this.errorMessage,
    this.sentAt,
    this.deliveredAt,
    required this.createdAt,
  });

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    return SmsMessage(
      id: json['id'] as String,
      deviceId: json['device_id'] as String?,
      direction: json['direction'] as String,
      phoneNumber: json['phone_number'] as String,
      message: json['message'] as String,
      simSlot: json['sim_slot'] as int? ?? 0,
      status: json['status'] as String,
      externalRef: json['external_ref'] as String?,
      errorMessage: json['error_message'] as String?,
      sentAt: json['sent_at'] != null ? DateTime.parse(json['sent_at'] as String) : null,
      deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class Webhook {
  final String id;
  final String url;
  final String secret;
  final List<String> events;
  final bool isActive;
  final DateTime createdAt;

  Webhook({
    required this.id,
    required this.url,
    required this.secret,
    required this.events,
    required this.isActive,
    required this.createdAt,
  });

  factory Webhook.fromJson(Map<String, dynamic> json) {
    List<String> parsedEvents = [];
    if (json['events'] is String) {
      try {
        parsedEvents = List<String>.from(jsonDecode(json['events'] as String) as List);
      } catch (_) {}
    } else if (json['events'] is List) {
      parsedEvents = List<String>.from(json['events'] as List);
    }

    return Webhook(
      id: json['id'] as String,
      url: json['url'] as String,
      secret: json['secret'] as String,
      events: parsedEvents,
      isActive: (json['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class WebhookLog {
  final String id;
  final String webhookId;
  final String? url;
  final String event;
  final String payload;
  final int? responseStatus;
  final String? error;
  final int durationMs;
  final DateTime createdAt;

  WebhookLog({
    required this.id,
    required this.webhookId,
    this.url,
    required this.event,
    required this.payload,
    this.responseStatus,
    this.error,
    required this.durationMs,
    required this.createdAt,
  });

  factory WebhookLog.fromJson(Map<String, dynamic> json) {
    return WebhookLog(
      id: json['id'] as String,
      webhookId: json['webhook_id'] as String,
      url: json['url'] as String?,
      event: json['event'] as String,
      payload: json['payload'] as String,
      responseStatus: json['response_status'] as int?,
      error: json['error'] as String?,
      durationMs: json['duration_ms'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ApiKey {
  final String id;
  final String name;
  final String key;
  final List<String> permissions;
  final bool isActive;
  final DateTime? lastUsedAt;
  final DateTime createdAt;

  ApiKey({
    required this.id,
    required this.name,
    required this.key,
    required this.permissions,
    required this.isActive,
    this.lastUsedAt,
    required this.createdAt,
  });

  factory ApiKey.fromJson(Map<String, dynamic> json) {
    List<String> parsedPerms = [];
    if (json['permissions'] is String) {
      try {
        parsedPerms = List<String>.from(jsonDecode(json['permissions'] as String) as List);
      } catch (_) {}
    } else if (json['permissions'] is List) {
      parsedPerms = List<String>.from(json['permissions'] as List);
    }

    return ApiKey(
      id: json['id'] as String,
      name: json['name'] as String,
      key: json['key'] as String,
      permissions: parsedPerms,
      isActive: (json['is_active'] as int? ?? 1) == 1,
      lastUsedAt: json['last_used_at'] != null ? DateTime.parse(json['last_used_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class GatewayStats {
  final int totalSent;
  final int totalDelivered;
  final int totalFailed;
  final int totalReceived;
  final int pendingQueue;
  final int activeDevices;
  final int totalDevices;

  GatewayStats({
    required this.totalSent,
    required this.totalDelivered,
    required this.totalFailed,
    required this.totalReceived,
    required this.pendingQueue,
    required this.activeDevices,
    required this.totalDevices,
  });

  factory GatewayStats.fromJson(Map<String, dynamic> json) {
    return GatewayStats(
      totalSent: json['totalSent'] as int? ?? 0,
      totalDelivered: json['totalDelivered'] as int? ?? 0,
      totalFailed: json['totalFailed'] as int? ?? 0,
      totalReceived: json['totalReceived'] as int? ?? 0,
      pendingQueue: json['pendingQueue'] as int? ?? 0,
      activeDevices: json['activeDevices'] as int? ?? 0,
      totalDevices: json['totalDevices'] as int? ?? 0,
    );
  }

  double get deliveryRate {
    if (totalSent == 0) return 100.0;
    return (totalDelivered / totalSent) * 100.0;
  }
}
