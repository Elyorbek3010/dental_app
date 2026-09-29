import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';

/// Represents a realtime queue update event received from the clinic display WebSocket.
class QueueUpdatedEvent {
  final int? clinicId;
  final int? queueId;
  final String type;

  const QueueUpdatedEvent({
    this.clinicId,
    this.queueId,
    required this.type,
  });

  @override
  String toString() =>
      'QueueUpdatedEvent(type: $type, clinicId: $clinicId, queueId: $queueId)';
}

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// Service providing real-time WebSocket connectivity for clinic queue updates.
///
/// Connects to `/api/public/ws/clinics/{clinicId}/display` and listens for
/// `queue_updated` and `display_updated` signals.
///
/// Features bounded exponential reconnect, safe error handling,
/// and full resource cleanup on dispose.
class QueueRealtimeService {
  QueueRealtimeService({ChannelFactory? channelFactory})
      : _channelFactory = channelFactory ?? ((uri) => WebSocketChannel.connect(uri));

  static final QueueRealtimeService instance = QueueRealtimeService();

  final ChannelFactory _channelFactory;
  final _eventController = StreamController<QueueUpdatedEvent>.broadcast();

  int? _activeClinicId;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _reconnectDelaySeconds = 1;
  bool _isDisposed = false;
  bool _isConnected = false;

  /// Stream of incoming queue update events.
  Stream<QueueUpdatedEvent> get events => _eventController.stream;

  /// True if currently connected to a WebSocket.
  bool get isConnected => _isConnected;

  /// Currently connected clinic ID.
  int? get activeClinicId => _activeClinicId;

  /// Connects to the WebSocket for [clinicId] with exponential backoff reconnect.
  void connect(int clinicId) {
    if (_isDisposed) return;
    if (_activeClinicId == clinicId && (_isConnected || _reconnectTimer != null)) {
      return;
    }

    disconnect();
    _activeClinicId = clinicId;
    _reconnectDelaySeconds = 1;
    _establishConnection();
  }

  void _establishConnection() {
    if (_isDisposed || _activeClinicId == null) return;

    _cleanupSocket();
    final uri = ApiConfig.clinicDisplayWsUri(_activeClinicId!);

    try {
      final channel = _channelFactory(uri);
      _channel = channel;

      _subscription = channel.stream.listen(
        (data) {
          _onData(data);
        },
        onError: (Object error) {
          debugPrint('[QueueRealtimeService] WebSocket error: $error');
          _onDisconnected();
        },
        onDone: () {
          debugPrint('[QueueRealtimeService] WebSocket connection closed');
          _onDisconnected();
        },
        cancelOnError: true,
      );

      _isConnected = true;
      _reconnectDelaySeconds = 1;
      debugPrint('[QueueRealtimeService] Connected to WebSocket at $uri');
    } catch (e) {
      debugPrint('[QueueRealtimeService] Failed to establish WebSocket: $e');
      _onDisconnected();
    }
  }

  void _onData(dynamic data) {
    if (data == null) return;
    try {
      final String text = data is String ? data : utf8.decode(data as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'] as String? ?? '';
      if (type == 'queue_updated' || type == 'display_updated') {
        final clinicId = decoded['clinic_id'] as int?;
        final queueId = decoded['queue_id'] as int?;
        final event = QueueUpdatedEvent(
          type: type,
          clinicId: clinicId,
          queueId: queueId,
        );
        if (!_eventController.isClosed) {
          _eventController.add(event);
        }
      }
    } catch (e) {
      // Safely ignore malformed or keepalive payloads (e.g. "pong")
      debugPrint('[QueueRealtimeService] Error parsing WebSocket payload: $e');
    }
  }

  void _onDisconnected() {
    _isConnected = false;
    _cleanupSocket();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_isDisposed || _activeClinicId == null) return;
    _reconnectTimer?.cancel();

    final delay = Duration(seconds: _reconnectDelaySeconds);
    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(1, 10);

    debugPrint('[QueueRealtimeService] Reconnecting in ${delay.inSeconds}s...');
    _reconnectTimer = Timer(delay, () {
      if (!_isDisposed && _activeClinicId != null) {
        _establishConnection();
      }
    });
  }

  void _cleanupSocket() {
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }

  /// Disconnects from the current clinic's WebSocket.
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupSocket();
    _activeClinicId = null;
    _reconnectDelaySeconds = 1;
  }

  /// Releases all resources.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    disconnect();
    _eventController.close();
  }
}
