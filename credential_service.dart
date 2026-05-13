import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// ============================================================
/// CredentialService — Servicio de credenciales rápidas.
///
/// Guarda el email y contraseña del último login exitoso de forma
/// encriptada en el dispositivo (flutter_secure_storage).
/// En el siguiente inicio de sesión, se puede usar biometría o
/// el PIN del sistema para acceder sin reescribir datos.
///
/// Solo funciona en Android e iOS. En Windows o Web,
/// [isSupported] devuelve false y el flujo normal de login aplica.
/// ============================================================
class CredentialService {
  // ── Singleton ─────────────────────────────────────────────
  CredentialService._internal();
  static final CredentialService instance = CredentialService._internal();
  factory CredentialService() => instance;
  // ──────────────────────────────────────────────────────────

  static const _keyEmail    = 'kofight_saved_email';
  static const _keyPassword = 'kofight_saved_password';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final LocalAuthentication _localAuth = LocalAuthentication();

  // ── SOPORTE ────────────────────────────────────────────────

  /// Retorna true en Android, iOS y Windows (donde existe autenticación del sistema).
  bool get isSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS || Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  // ── CREDENCIALES ───────────────────────────────────────────

  /// Guarda email y contraseña de forma encriptada tras un login exitoso.
  Future<void> saveCredentials(String email, String password) async {
    if (!isSupported) return;
    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyPassword, value: password);
  }

  /// Carga las credenciales guardadas. Retorna null si no hay ninguna.
  Future<Map<String, String>?> loadCredentials() async {
    if (!isSupported) return null;
    final email    = await _storage.read(key: _keyEmail);
    final password = await _storage.read(key: _keyPassword);
    if (email == null || password == null) return null;
    return {'email': email, 'password': password};
  }

  /// Retorna true si hay credenciales guardadas en el dispositivo.
  Future<bool> hasSavedCredentials() async {
    if (!isSupported) return false;
    final email = await _storage.read(key: _keyEmail);
    return email != null && email.isNotEmpty;
  }

  /// Retorna solo el email guardado (para mostrarlo en la UI sin exponer la contraseña).
  Future<String?> getSavedEmail() async {
    if (!isSupported) return null;
    return _storage.read(key: _keyEmail);
  }

  /// Borra todas las credenciales guardadas (logout definitivo).
  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyEmail);
    await _storage.delete(key: _keyPassword);
  }

  // ── BIOMETRÍA ──────────────────────────────────────────────

  /// Retorna true si el dispositivo tiene biometría o PIN/Windows Hello configurado.
  Future<bool> canUseBiometrics() async {
    if (!isSupported) return false;
    try {
      // Verificar si el dispositivo soporta autenticación
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!isDeviceSupported) return false;

      // En Android/iOS verificar también si hay biometría o PIN enrollado
      final canCheck = await _localAuth.canCheckBiometrics;
      return canCheck || isDeviceSupported;
    } on PlatformException catch (e) {
      debugPrint('[CredentialService] canUseBiometrics error: $e');
      return false;
    }
  }

  /// Solicita al usuario que se autentique con huella, Face ID o PIN del sistema.
  /// Retorna true si la autenticación fue exitosa.
  Future<bool> authenticate() async {
    if (!isSupported) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Autentícate para acceder a KOFIGHT',
        options: const AuthenticationOptions(
          biometricOnly: false, // Permite también PIN/patrón como fallback
          stickyAuth: true,     // Mantiene el diálogo si el usuario cambia de app
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
