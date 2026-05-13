import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../engine/combat_engine.dart';

/// ============================================================
/// ArenaService — Singleton que gestiona toda la comunicación
/// WebSocket (Socket.IO) con el servidor Arena PVP.
///
/// Uso:
///   ArenaService.instance.joinQueue(team, deck);
///   ArenaService.instance.onMatchFound.listen((data) { ... });
/// ============================================================
class ArenaService {
  // ── Singleton ──────────────────────────────────────────────
  ArenaService._internal();
  static final ArenaService instance = ArenaService._internal();
  // Usamos conexión directa WebSocket para evadir bloqueos de firewall HTTP o poliza de Cleartext en Android.
  static const String _serverUrl = 'ws://YOUR_SERVER_IP:3000';

  IO.Socket? _socket;

  // ── Streams públicos ────────────────────────────────────────
  final _matchFoundCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _turnResultCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _turnStartCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _receiveEmoteCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _opponentDisconnCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  final _opponentReconnCtrl = StreamController<void>.broadcast();
  final _combatCancelledCtrl = StreamController<String>.broadcast();
  final _victoryByDisconnCtrl = StreamController<void>.broadcast();
  final _pingCtrl = StreamController<int>.broadcast();

  /// Emitido cuando el servidor encontró un oponente.
  /// Payload: { roomId, opponentName, opponentTeam, myTeam (estado inicial) }
  Stream<Map<String, dynamic>> get onMatchFound => _matchFoundCtrl.stream;

  /// Emitido tras la resolución de cada turno.
  /// Payload: TurnResult serializado + estados finales de ambos equipos.
  Stream<Map<String, dynamic>> get onTurnResult => _turnResultCtrl.stream;

  /// Emitido al inicio de cada turno (sincroniza el timer).
  Stream<Map<String, dynamic>> get onTurnStart => _turnStartCtrl.stream;

  /// Emitido cuando un jugador envía un emote.
  /// Payload: { senderId, emoteId }
  Stream<Map<String, dynamic>> get onReceiveEmote => _receiveEmoteCtrl.stream;

  /// El oponente se desconectó. Payload: { secondsToReconnect }
  Stream<Map<String, dynamic>> get onOpponentDisconnected =>
      _opponentDisconnCtrl.stream;

  /// El oponente volvió a conectarse.
  Stream<void> get onOpponentReconnected => _opponentReconnCtrl.stream;

  /// Combate cancelado (desconexión antes del turno 4). Payload: motivo.
  Stream<String> get onCombatCancelled => _combatCancelledCtrl.stream;

  /// Victoria automática por abandono del rival (turno ≥ 4).
  Stream<void> get onVictoryByDisconnect => _victoryByDisconnCtrl.stream;

  /// Emite el ping en ms cada ~3 segundos. >200ms = conexión inestable.
  Stream<int> get onPing => _pingCtrl.stream;

  // ── Estado interno ──────────────────────────────────────────
  String? _currentRoomId;
  String? get currentRoomId => _currentRoomId;

  bool get isConnected => _socket?.connected ?? false;

  // ── Ping periódico ─────────────────────────────────────────
  Timer? _pingTimer;
  int? _pingSentAt;

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_socket == null || !_socket!.connected) return;
      _pingSentAt = DateTime.now().millisecondsSinceEpoch;
      _socket!.emit('arena:ping');
    });
  }

  void _stopPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // ── Conexión ────────────────────────────────────────────────

  /// Conecta al servidor WebSocket usando el token JWT de Supabase.
  Future<void> _connect() async {
    if (_socket != null && _socket!.connected) return;

    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('Usuario no autenticado');

    _socket = IO.io(
      // IMPORTANTE: Usar solo la URL base SIN el namespace en la URL.
      // El cliente Dart de socket_io_client trata el path de la URL como
      // el path de socket.io (ej: /arena → /arena?EIO=4), NO como namespace.
      // La ruta correcta que Nginx proxifica es /socket.io/ (ruta por defecto).
      _serverUrl,
      IO.OptionBuilder()
          // Forzar WebSocket puro y saltarse el polling HTTP, que suele ser problemático.
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.connect();
    _registerListeners();
    _startPingLoop();
  }

  void _registerListeners() {
    final s = _socket!;

    // -- DEBUG LOGS DE CONEXION --
    s.onConnect((_) {
      debugPrint('[ArenaService] CONECTADO a Socket.IO con id: ${s.id}');
      // Si venimos de una reconexión con sala activa, notificar al servidor.
      // Usamos Future.delayed para asegurar que la conexión esté estable.
      if (_currentRoomId != null) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (s.connected && _currentRoomId != null) {
            debugPrint('[ArenaService] Reconectando a sala: $_currentRoomId');
            s.emit('arena:reconnect', {'roomId': _currentRoomId});
          }
        });
      }
    });

    s.onConnectError((data) {
      debugPrint('[ArenaService] ERROR DE CONEXION: $data');
      _combatCancelledCtrl.add('Error al conectar con el servidor.');
    });

    s.onError((data) {
      debugPrint('[ArenaService] SOCKET ERROR: $data');
    });

    s.onConnectTimeout((data) {
      debugPrint('[ArenaService] CONEXION TIMEOUT: $data');
    });

    s.onDisconnect((_) {
      debugPrint('[ArenaService] DESCONECTADO');
    });
    // ----------------------------

    s.on('arena:match_found', (data) {
      debugPrint('[ArenaService] MATCH FOUND: $data');
      final map = Map<String, dynamic>.from(data as Map);
      _currentRoomId = map['roomId'] as String?;
      _matchFoundCtrl.add(map);
    });

    s.on('arena:turn_result', (data) {
      debugPrint('[ArenaService] TURN RESULT RECIBIDO');
      _turnResultCtrl.add(Map<String, dynamic>.from(data as Map));
    });

    s.on('arena:turn_start', (data) {
      debugPrint('[ArenaService] TURN START');
      _turnStartCtrl.add(Map<String, dynamic>.from(data as Map));
    });

    s.on('arena:receive_emote', (data) {
      _receiveEmoteCtrl.add(Map<String, dynamic>.from(data as Map));
    });

    s.on('arena:opponent_disconnected', (data) {
      debugPrint('[ArenaService] OPC DESCONECTADO');
      _opponentDisconnCtrl.add(Map<String, dynamic>.from(data as Map));
    });

    s.on('arena:opponent_reconnected', (_) {
      debugPrint('[ArenaService] OPC RECONECTADO');
      _opponentReconnCtrl.add(null);
    });

    s.on('arena:combat_cancelled', (data) {
      debugPrint('[ArenaService] OP COMBAT AORTADO');
      final msg = (data as Map)['reason']?.toString() ?? 'Combate cancelado';
      _combatCancelledCtrl.add(msg);
    });

    s.on('arena:pong', (_) {
      if (_pingSentAt != null) {
        final ms = DateTime.now().millisecondsSinceEpoch - _pingSentAt!;
        _pingCtrl.add(ms);
        _pingSentAt = null;
      }
    });

    s.on('arena:error', (data) {
      debugPrint('[ArenaService] ERROR RECIBIDO DEL SERVIDOR: $data');
    });

    s.on('arena:victory', (_) {
      debugPrint('[ArenaService] VISTORIA POR DESCONEXION');
      _victoryByDisconnCtrl.add(null);
    });
  }

  // ── API Pública ─────────────────────────────────────────────

  /// Se une a la cola de matchmaking enviando el equipo y mazo al servidor.
  Future<void> joinQueue({
    required List<Fighter> team,
    required List<Map<String, dynamic>> deck,
    required String username,
  }) async {
    await _connect();
    _socket!.emit('arena:join_queue', {
      'team': team.map((f) => f.toJson()).toList(),
      'deck': deck,
      'username': username,
    });
  }

  /// Envía un emote al servidor para que lo transmita.
  void sendEmote(String emoteId) {
    _socket?.emit('arena:send_emote', {
      'roomId': _currentRoomId,
      'emoteId': emoteId,
    });
  }

  /// Envía las asignaciones de cartas del turno actual al servidor.
  void submitTurn({
    required Map<String, List<Map<String, dynamic>>> assignments,
    required Map<String, String> targetOverrides,
  }) {
    _socket?.emit('arena:submit_turn', {
      'roomId': _currentRoomId,
      'assignments': assignments,
      'targetOverrides': targetOverrides,
    });
  }

  /// Cancela la búsqueda de partida antes de encontrar rival.
  void leaveQueue() {
    _socket?.emit('arena:leave_queue', {});
  }

  /// Desconecta el socket limpiamente al salir del modo Arena.
  void disconnect() {
    _stopPingLoop();
    _currentRoomId = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  /// Limpia los streams al destruir el servicio.
  void dispose() {
    disconnect();
    _matchFoundCtrl.close();
    _turnResultCtrl.close();
    _turnStartCtrl.close();
    _receiveEmoteCtrl.close();
    _opponentDisconnCtrl.close();
    _opponentReconnCtrl.close();
    _combatCancelledCtrl.close();
    _victoryByDisconnCtrl.close();
    _pingCtrl.close();
  }
}
