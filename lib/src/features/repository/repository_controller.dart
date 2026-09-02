import 'package:gitflu/src/features/repository/recent_repository_store.dart';
import 'package:gitflu/src/features/settings/git_settings_controller.dart';
import 'package:gitflu/src/backend/domain.dart';
import 'package:gitflu/src/backend/error.dart';
import 'package:gitflu/src/backend/git_gateway.dart';
import 'package:flutter/foundation.dart';

class RepositoryState {
  const RepositoryState({
    this.recentRepositories = const <RecentRepository>[],
    this.gitInstallation,
    this.error,
    this.errorMessage,
    this.openedRepository,
    this.isLoading = false,
    this.isOpening = false,
  });

  final List<RecentRepository> recentRepositories;
  final GitInstallation? gitInstallation;
  final GitError? error;
  final String? errorMessage;
  final RepositoryOpened? openedRepository;
  final bool isLoading;
  final bool isOpening;

  bool get canOpen => gitInstallation != null && !isOpening;

  RepositoryState copyWith({
    List<RecentRepository>? recentRepositories,
    GitInstallation? gitInstallation,
    bool clearGitInstallation = false,
    GitError? error,
    bool clearError = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    RepositoryOpened? openedRepository,
    bool clearOpenedRepository = false,
    bool? isLoading,
    bool? isOpening,
  }) {
    return RepositoryState(
      recentRepositories: recentRepositories ?? this.recentRepositories,
      gitInstallation: clearGitInstallation
          ? null
          : gitInstallation ?? this.gitInstallation,
      error: clearError ? null : error ?? this.error,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      openedRepository: clearOpenedRepository
          ? null
          : openedRepository ?? this.openedRepository,
      isLoading: isLoading ?? this.isLoading,
      isOpening: isOpening ?? this.isOpening,
    );
  }
}

class RepositoryController extends ChangeNotifier {
  RepositoryController({
    required this.gateway,
    required this.recentStore,
    this.gitSettingsController,
  });

  final GitGateway gateway;
  final RecentRepositoryStore recentStore;
  final GitSettingsController? gitSettingsController;
  RepositoryState _state = const RepositoryState();

  RepositoryState get state => _state;

  Future<void> initialize() async {
    // Load recent paths independently so they remain visible even when Git is
    // missing or an outdated executable is configured.
    _setState(_state.copyWith(isLoading: true, clearError: true));
    final recentRepositories = await recentStore.load();

    try {
      final installation = await _loadGitInstallation();
      _setState(
        _state.copyWith(
          recentRepositories: recentRepositories,
          gitInstallation: installation,
          isLoading: false,
          clearError: true,
          clearErrorMessage: true,
        ),
      );
    } on GitError catch (error) {
      _setState(
        _state.copyWith(
          recentRepositories: recentRepositories,
          clearGitInstallation: true,
          error: error,
          errorMessage: error.userMessage,
          isLoading: false,
        ),
      );
    }
  }

  Future<void> openPath(String path) async {
    // The screen passes only a path. The gateway/backend performs all Git
    // validation and returns a canonical repository root.
    if (!state.canOpen) return;
    _setState(
      _state.copyWith(
        isOpening: true,
        clearError: true,
        clearErrorMessage: true,
      ),
    );
    try {
      final openedRepository = await gateway.openRepository(path);
      await recentStore.add(openedRepository.root);
      _setState(
        _state.copyWith(
          recentRepositories: await recentStore.load(),
          openedRepository: openedRepository,
          isOpening: false,
          clearError: true,
          clearErrorMessage: true,
        ),
      );
    } on GitError catch (error) {
      _setState(
        _state.copyWith(
          error: error,
          errorMessage: error.userMessage,
          isOpening: false,
        ),
      );
    }
  }

  Future<void> removeRecent(RecentRepository repository) async {
    await recentStore.remove(repository.path);
    _setState(_state.copyWith(recentRepositories: await recentStore.load()));
  }

  void closeRepository() {
    _setState(_state.copyWith(clearOpenedRepository: true));
  }

  void applyGitSettings(GitSettingsState settings) {
    if (settings.installation != null) {
      _setState(
        _state.copyWith(
          gitInstallation: settings.installation,
          clearError: true,
          clearErrorMessage: true,
        ),
      );
    } else if (settings.error != null) {
      _setState(
        _state.copyWith(
          clearGitInstallation: true,
          error: settings.error,
          errorMessage: settings.error!.userMessage,
        ),
      );
    }
  }

  Future<GitInstallation> _loadGitInstallation() async {
    final settings = gitSettingsController;
    if (settings == null) return gateway.getGitInstallation();
    await settings.initialize();
    if (settings.state.installation case final installation?) {
      return installation;
    }
    if (settings.state.error case final error?) throw error;
    throw const GitError(
      category: GitErrorCategory.internal,
      userMessage: 'Git settings could not be loaded.',
      diagnostic: 'settings controller returned no installation or error',
      retryable: true,
    );
  }

  void _setState(RepositoryState state) {
    _state = state;
    notifyListeners();
  }
}
