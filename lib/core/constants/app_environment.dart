/// Build-time environment from `--dart-define=APP_ENV=...` (see `.vscode/launch.json`).
enum AppEnvironment {
  development,
  staging,
  production,
}

class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  /// Must be `const` — on web, non-const [String.fromEnvironment] throws at runtime.
  static const String _rawAppEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static final AppEnvironment current = _parse(_rawAppEnv);

  static AppEnvironment _parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'staging':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      default:
        return AppEnvironment.development;
    }
  }
}
