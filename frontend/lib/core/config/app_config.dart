class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const demoRole = String.fromEnvironment('DEMO_ROLE', defaultValue: '');

  static const demoAuthToken = String.fromEnvironment('DEMO_AUTH_TOKEN', defaultValue: '');
}