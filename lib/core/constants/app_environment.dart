/// Build-time environment from `--dart-define=APP_ENV=...` (see `.vscode/launch.json`).
enum AppEnvironment {
  development,
  staging,
  production,
}

class AppEnvironmentConfig {
  AppEnvironmentConfig._();

  static final AppEnvironment current = _parse(
    String.fromEnvironment('APP_ENV', defaultValue: 'development'),
  );

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
