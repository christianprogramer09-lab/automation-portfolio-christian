import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'credential_service.dart';

/// ============================================================
/// AuthService — Servicio de autenticación con Supabase.
/// Es un SINGLETON para que el activeSessionToken sea compartido
/// entre todas las pantallas (auth_overlay, hub_screen, main).
/// ============================================================
class AuthService {
  // ─── Singleton ────────────────────────────────────────────
  AuthService._internal();
  static final AuthService instance = AuthService._internal();
  factory AuthService() => instance;
  // ──────────────────────────────────────────────────────────

  final GoTrueClient _auth = Supabase.instance.client.auth;
  final SupabaseClient _client = Supabase.instance.client;

  /// Token de sesión único para esta instancia de la app.
  /// Se genera al hacer login y se guarda en la BD para
  /// detectar si otra sesión se inicia en otro dispositivo.
  String? activeSessionToken;

  /// Genera un token aleatorio de 32 caracteres hexadecimales.
  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Actualiza el current_session_token del jugador en Supabase.
  Future<void> _pushSessionToken(String userId, String token) async {
    await _client
        .from('players')
        .update({'current_session_token': token})
        .eq('id', userId);
  }

  /// Inicia sesión con correo o nombre de usuario y genera un token de sesión único.
  Future<AuthResponse> signIn({
    required String identifier,
    required String password,
  }) async {
    String email;

    if (identifier.contains('@')) {
      email = identifier;
    } else {
      try {
        final response = await _client
            .from('players')
            .select('email')
            .eq('username', identifier)
            .single();
        email = response['email'] as String;
      } catch (e) {
        throw AuthException(
          'Usuario no encontrado. Verifica tu nombre de usuario.',
        );
      }
    }

    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );

    // Generar y guardar el token de sesión único.
    if (response.user != null) {
      activeSessionToken = _generateToken();
      await _pushSessionToken(response.user!.id, activeSessionToken!);
      // Guardar credenciales para el acceso rápido futuro.
      await CredentialService().saveCredentials(email, password);
    }

    return response;
  }

  /// Registra un nuevo usuario y genera un token de sesión inicial.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await _auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );

    if (response.user != null) {
      activeSessionToken = _generateToken();
      // El trigger de Supabase puede tardar en crear el registro en players,
      // así que esperamos un momento antes de actualizarlo.
      await Future.delayed(const Duration(seconds: 2));
      await _pushSessionToken(response.user!.id, activeSessionToken!);
      // Guardar credenciales para el acceso rápido futuro.
      await CredentialService().saveCredentials(email, password);
    }

    return response;
  }

  /// Cierra la sesión y limpia el token local.
  /// Si [permanent] es true, también borra las credenciales guardadas en el dispositivo,
  /// forzando al usuario a ingresar email y contraseña en el próximo inicio.
  Future<void> signOut({bool permanent = false}) async {
    activeSessionToken = null;
    if (permanent) {
      await CredentialService().clearCredentials();
    }
    await _auth.signOut();
  }

  /// Retorna el usuario actualmente autenticado, o null si no hay sesión.
  User? get currentUser => _auth.currentUser;

  /// Retorna true si hay un usuario autenticado.
  bool get isAuthenticated => _auth.currentUser != null;
}
