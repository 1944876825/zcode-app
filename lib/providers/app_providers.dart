import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

import '../core/network/zcode_api_client.dart';
import '../core/relay/relay_client.dart';
import '../core/relay/relay_protocol.dart';
import '../core/storage/secure_storage.dart';
import '../data/models/workspace.dart';
import '../data/models/zcode_session.dart';
import '../data/repositories/repositories.dart';

// ================================================================
// 基础设施 Providers
// ================================================================

final loggerProvider = Provider<Logger>((ref) {
  final logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: false,
    ),
  );
  ref.onDispose(logger.close);
  return logger;
});

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final preferencesProvider =
    FutureProvider<PreferencesService>((ref) async {
  final prefs = PreferencesService();
  await prefs.init();
  return prefs;
});

final zcodeApiClientProvider = Provider<ZcodeApiClient>((ref) {
  return ZcodeApiClient();
});

// ================================================================
// Session / Auth
// ================================================================

/// 当前会话
final sessionProvider =
    StateNotifierProvider<SessionNotifier, AsyncValue<ZcodeSession?>>((ref) {
  return SessionNotifier(ref.watch(secureStorageProvider));
});

class SessionNotifier extends StateNotifier<AsyncValue<ZcodeSession?>> {
  final SecureStorageService _storage;

  SessionNotifier(this._storage) : super(const AsyncValue.loading()) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final session = await _storage.getSession();
      if (session != null && session.isValid) {
        state = AsyncValue.data(session);
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loginWithSession(ZcodeSession session) async {
    await _storage.saveSession(session);
    state = AsyncValue.data(session);
  }

  Future<void> logout() async {
    await _storage.clearSession();
    state = const AsyncValue.data(null);
  }
}

// ================================================================
// RelayClient
// ================================================================

/// 当前活跃的 RelayClient (依赖 session)
final relayClientProvider = Provider<RelayClient?>((ref) {
  final session = ref.watch(sessionProvider);

  return session.whenOrNull(
    data: (session) {
      if (session == null || !session.isValid) return null;

      final logger = ref.read(loggerProvider);
      final config = RelayConfig(
        wsUrl: 'wss://zcode.z.ai/ws?mid=${session.mid}',
        deviceSid: session.deviceSid,
        passHash: session.passHash,
        cookie: session.cookie,
        deviceName: session.deviceName,
      );

      final client = RelayClient(
        config: config,
        logger: (level, message) {
          switch (level) {
            case 'error':
              logger.e('[Relay] $message');
            case 'warn':
              logger.w('[Relay] $message');
            case 'info':
              logger.i('[Relay] $message');
            default:
              logger.d('[Relay] $message');
          }
        },
      );

      ref.onDispose(client.dispose);
      return client;
    },
  );
});

/// Relay 连接状态
final relayConnectionStateProvider = StreamProvider<RelayConnectionState>((ref) async* {
  final client = ref.watch(relayClientProvider);
  if (client == null) return;
  yield* client.onStateChange;
});

// ================================================================
// Repositories
// ================================================================

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(secureStorageProvider));
});

final workspaceRepositoryProvider = Provider<WorkspaceRepository?>((ref) {
  final client = ref.watch(relayClientProvider);
  if (client == null) return null;
  return WorkspaceRepository(client);
});

final chatRepositoryProvider = Provider<ChatRepository?>((ref) {
  final client = ref.watch(relayClientProvider);
  if (client == null) return null;
  return ChatRepository(client);
});

// ================================================================
// 工作区列表
// ================================================================

/// 工作区列表
final workspaceListProvider =
    StateNotifierProvider<WorkspaceListNotifier, AsyncValue<List<Workspace>>>((ref) {
  final repo = ref.watch(workspaceRepositoryProvider);
  return WorkspaceListNotifier(repo, ref);
});

class WorkspaceListNotifier
    extends StateNotifier<AsyncValue<List<Workspace>>> {
  final WorkspaceRepository? _repo;
  final Ref _ref;

  WorkspaceListNotifier(this._repo, this._ref)
      : super(const AsyncValue.loading());

  Future<void> load() async {
    if (_repo == null) {
      state = AsyncValue.error('No relay client', StackTrace.current);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final resp = await _repo!.bootstrap();
      final workspaces = Workspace.parseList(resp);
      final tasks = Workspace.parseTasks(resp);
      _ref.read(allTasksProvider.notifier).state = tasks;
      state = AsyncValue.data(workspaces);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    if (_repo == null) return;
    try {
      final resp = await _repo!.refresh();
      final workspaces = Workspace.parseList(resp);
      final tasks = Workspace.parseTasks(resp);
      _ref.read(allTasksProvider.notifier).state = tasks;
      state = AsyncValue.data(workspaces);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ================================================================
// 当前选中的工作区
// ================================================================

final selectedWorkspaceProvider = StateProvider<Workspace?>((ref) => null);

// ================================================================
// 当前工作区的任务列表
// ================================================================

final taskListProvider = FutureProvider.family<List<Task>, String>((ref, workspaceKey) async {
  // 任务从 bootstrap 响应中获取 (result.tasks 含所有工作区任务)
  final workspacesAsync = ref.watch(workspaceListProvider);
  return workspacesAsync.maybeWhen(
    data: (_) {
      // 任务缓存在 allTasksProvider (bootstrap 只取一次, 任务随之确定)
      final allTasks = ref.watch(allTasksProvider);
      return allTasks.where((t) => t.workspaceKey == workspaceKey).toList();
    },
    orElse: () => <Task>[],
  );
});

/// 所有任务 (从 bootstrap 解析, 供 UI 筛选)
final allTasksProvider = StateProvider<List<Task>>((ref) => const <Task>[]);
