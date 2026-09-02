import 'package:branchline/src/backend/domain.dart';
import 'package:branchline/src/backend/error.dart';
import 'package:branchline/src/backend/git_gateway.dart';
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

  GitSettingsState get state => _state;

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    _setState(const GitSettingsState(isLoading: true));

    try {
      final configuredPath = preferences.getString(pathKey);
      final installation = configuredPath == null || configuredPath.isEmpty
          ? await gateway.getGitInstallation()
          : await gateway.configureGitPath(configuredPath);
      _setState(GitSettingsState(installation: installation));
    } on GitError catch (error) {
      _setState(GitSettingsState(error: error));
    }
  }

  Future<void> configurePath(String path) async {
    _setState(const GitSettingsState(isLoading: true));
    try {
      final installation = await gateway.configureGitPath(path);
      await preferences.setString(pathKey, path);
      _setState(GitSettingsState(installation: installation));
    } on GitError catch (error) {
      _setState(GitSettingsState(error: error));
    }
  }

  Future<void> retry() => initialize(force: true);

  void _setState(GitSettingsState state) {
    _state = state;
    notifyListeners();
  }
}
