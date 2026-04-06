/// Build-time environment: `--dart-define=APP_ENV=staging|production`
enum AppEnvironment { development, staging, production }

AppEnvironment parseAppEnvironment() {
  const raw = String.fromEnvironment('APP_ENV', defaultValue: 'development');
  return switch (raw) {
    'production' => AppEnvironment.production,
    'staging' => AppEnvironment.staging,
    _ => AppEnvironment.development,
  };
}

bool get isProduction => parseAppEnvironment() == AppEnvironment.production;
