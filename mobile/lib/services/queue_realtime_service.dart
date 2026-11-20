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
  QueueRealtimeService({
    ChannelFactory? channelFactory,
    this.keepaliveInterval = const Duration(seconds: 25),
    this.pongTimeout = const Duration(seconds: 10),
  }) : _channelFactory = channelFactory ?? ((uri) => WebSocketChannel.connect(uri));

  static QueueRealtimeService _instance = QueueRealtimeService();
  static QueueRealtimeService get instance => _instance;

  @visibleForTesting
  static set instance(QueueRealtimeService s) => _instance = s;

  final ChannelFactory _channelFactory;
  final Duration keepaliveInterval;
  final Duration pongTimeout;

  final _eventController = StreamController<QueueUpdatedEvent>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _reconnectedController = StreamController<int>.broadcast();
  final Set<Object> _consumers = <Object>{};

  int? _activeClinicId;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _keepaliveTimer;
  Timer? _pongTimeoutTimer;
  int _reconnectDelaySeconds = 1;
  bool _isDisposed = false;
  bool _isConnected = false;
  bool _hasConfirmedHandshake = false;
  bool _hasLostConnection = false;
  bool _awaitingPong = false;

  /// Stream of incoming queue update events.
  Stream<QueueUpdatedEvent> get events => _eventController.stream;

  /// Broadcasts `true` when socket handshake/messages confirm healthy connectivity,
  /// and `false` when an active/established socket disconnects or times out.
  Stream<bool> get connectionStates => _connectionStateController.stream;

  /// Emits the clinicId when a WebSocket connection recovers after a drop/timeout.
  Stream<int> get onReconnected => _reconnectedController.stream;

  /// True if a socket channel is currently open.
  bool get isConnected => _isConnected;

  /// True if the current socket has received at least one valid frame (`connected`/`pong`/event).
  bool get isConnectionConfirmed => _hasConfirmedHandshake;

  /// Currently connected clinic ID.
  int? get activeClinicId => _activeClinicId;

  /// Connects on behalf of a UI [consumer] without breaking other active listeners.
  void connectForConsumer(Object consumer, int clinicId) {
    if (_isDisposed) return;
    _consumers.add(consumer);
    ensureConnected(clinicId);
  }

  /// Releases a UI [consumer] and closes the socket only when no consumers remain.
  void disconnectConsumer(Object consumer) {
    _consumers.remove(consumer);
    if (_consumers.isEmpty) {
      disconnect();
    }
  }

  /// Connects to [clinicId], optionally forcing a fresh socket if stale.
  void ensureConnected(int clinicId, {bool forceReconnect = false}) {
    if (_isDisposed) return;
    if (forceReconnect) {
      _closeConnection();
    }
    connect(clinicId);
  }

  /// Connects to the WebSocket for [clinicId] with exponential backoff reconnect.
  void connect(int clinicId) {
    if (_isDisposed) return;
    if (_activeClinicId == clinicId && (_isConnected || _reconnectTimer != null)) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupSocket();
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
      _hasConfirmedHandshake = false;
      _awaitingPong = false;
      _startKeepalive();
      debugPrint('[QueueRealtimeService] Connected to WebSocket at $uri');
    } catch (e) {
      debugPrint('[QueueRealtimeService] Failed to establish WebSocket: $e');
      _onDisconnected();
    }
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(keepaliveInterval, (_) {
      if (_isDisposed || !_isConnected || _channel == null) return;
      if (_awaitingPong) {
        debugPrint('[QueueRealtimeService] Previous keepalive ping unacknowledged; disconnecting');
        _onDisconnected();
        return;
      }
      try {
        _awaitingPong = true;
        _pongTimeoutTimer?.cancel();
        _pongTimeoutTimer = Timer(pongTimeout, _handlePongTimeout);
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      } catch (e) {
        debugPrint('[QueueRealtimeService] Keepalive ping failed: $e');
        _onDisconnected();
      }
    });
  }

  void _handlePongTimeout() {
    if (_isDisposed || !_isConnected || !_awaitingPong) return;
    debugPrint(
      '[QueueRealtimeService] Keepalive pong timeout (${pongTimeout.inSeconds}s); '
      'disconnecting stalled WebSocket',
    );
    _onDisconnected();
  }

  void _clearPongTimeout() {
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
    _awaitingPong = false;
  }

  void _onData(dynamic data) {
    if (data == null) return;
    try {
      final String text = data is String ? data : utf8.decode(data as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['type'] as String? ?? '';
      if (type == 'pong') {
        _clearPongTimeout();
      }

      // Confirm live connection and reset backoff only on actual server traffic.
      final wasHandshakeConfirmed = _hasConfirmedHandshake;
      _hasConfirmedHandshake = true;
      _reconnectDelaySeconds = 1;
      if (!wasHandshakeConfirmed) {
        if (!_connectionStateController.isClosed) {
          _connectionStateController.add(true);
        }
        if (_hasLostConnection) {
          _hasLostConnection = false;
          if (!_reconnectedController.isClosed && _activeClinicId != null) {
            _reconnectedController.add(_activeClinicId!);
          }
        }
      }

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
      // Safely ignore malformed or non-JSON keepalive payloads
      debugPrint('[QueueRealtimeService] Error parsing WebSocket payload: $e');
    }
  }

  void _onDisconnected() {
    final wasConfirmed = _hasConfirmedHandshake;
    _isConnected = false;
    _cleanupSocket();
    if (wasConfirmed) {
      _hasLostConnection = true;
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(false);
      }
    }
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
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _clearPongTimeout();
    _hasConfirmedHandshake = false;
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }

  void _closeConnection() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _hasLostConnection = false;
    _cleanupSocket();
    _activeClinicId = null;
    _reconnectDelaySeconds = 1;
  }

  /// Disconnects from the current clinic's WebSocket.
  void disconnect() {
    _consumers.clear();
    _closeConnection();
  }

  /// Releases all resources.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    disconnect();
    _eventController.close();
    _connectionStateController.close();
    _reconnectedController.close();
  }
}
