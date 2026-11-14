import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_service.dart';

class DashboardSocket {
  static final DashboardSocket _instance = DashboardSocket._internal();
  factory DashboardSocket() => _instance;
  DashboardSocket._internal();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _isConnected = false;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _isConnected;
  Stream<bool> get connectionStream => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  void connect() {
    _reconnectTimer?.cancel();

    // Convert http/https baseUrl to ws/wss
    String wsUrl = ApiService.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    wsUrl = '$wsUrl/ws/dashboard';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _channel!.ready.then((_) {
        _isConnected = true;
        _connectionStateController.add(true);
      }).catchError((_) {
        _onDisconnected();
      });

      _channel!.stream.listen(
        (data) {
          try {
            final map = jsonDecode(data.toString()) as Map<String, dynamic>;
            _eventController.add(map);
          } catch (_) {}
        },
        onDone: () => _onDisconnected(),
        onError: (_) => _onDisconnected(),
      );
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onDisconnected() {
    _isConnected = false;
    _connectionStateController.add(false);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () => connect());
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _connectionStateController.add(false);
  }
}
