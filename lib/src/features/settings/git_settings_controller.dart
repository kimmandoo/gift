import 'package:gitflu/src/backend/domain.dart';
import 'package:gitflu/src/backend/error.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GitSettingsState {
  const GitSettingsState({
    this.installation,
    this.error,
    this.isLoading = false,
  });

  final GitInstallation? installation;
  final GitError? error;
  final bool isLoading;
}

class GitSettingsController extends ChangeNotifier {
  GitSettingsController({required this.gateway, required this.preferences});

  static const pathKey = 'git_executable_path';

  final GitGateway gateway;
  final SharedPreferences preferences;
  GitSettingsState _state = const GitSettingsState();
  bool _initialized = false;
  bool _disposed = false;
  int _requestGeneration = 0;

  GitSettingsState get state => _state;

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
    final request = ++_requestGeneration;
    _initialized = true;
    _setState(const GitSettingsState(isLoading: true));

    try {
      final configuredPath = preferences.getString(pathKey);
      final installation = configuredPath == null || configuredPath.isEmpty
          ? await gateway.getGitInstallation()
          : await gateway.configureGitPath(configuredPath);
      if (request == _requestGeneration) {
        _setState(GitSettingsState(installation: installation));
      }
    } on GitError catch (error) {
      if (request == _requestGeneration) {
        _setState(GitSettingsState(error: error));
      }
    }
  }

  Future<void> configurePath(String path) async {
    final request = ++_requestGeneration;
    _setState(const GitSettingsState(isLoading: true));
    try {
      final installation = await gateway.configureGitPath(path);
      if (request != _requestGeneration || _disposed) return;
      await preferences.setString(pathKey, installation.executablePath);
      if (request == _requestGeneration) {
        _setState(GitSettingsState(installation: installation));
      }
    } on GitError catch (error) {
      if (request == _requestGeneration) {
        _setState(GitSettingsState(error: error));
      }
    }
  }

  Future<void> retry() => initialize(force: true);

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    super.dispose();
  }

  void _setState(GitSettingsState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }
}
