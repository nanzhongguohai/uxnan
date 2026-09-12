import 'package:equatable/equatable.dart';
import 'package:uxnan/domain/enums/thread_status.dart';
import 'package:uxnan/domain/enums/thread_sync_state.dart';

/// A conversation thread handled by a coding agent.
///
/// Mirrors the entity defined in `architecture/02a-system-architecture.md`
/// (section 5.1.1). [agentId] holds the agent's wire identifier (see
/// `AgentId.wireId`) so a thread is portable across adapters.
class Thread extends Equatable {
  /// Creates a [Thread].
  const Thread({
    required this.id,
    required this.title,
    required this.agentId,
    required this.syncState,
    required this.status,
    this.projectId,
    this.deviceId,
    this.cwd,
    this.worktreePath,
    this.model,
    this.lastActivity,
    this.createdAt,
  });

  /// Parses a [Thread] from a wire JSON payload.
  factory Thread.fromJson(Map<String, dynamic> json) {
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'] ?? json['lastActivity'];
    return Thread(
      id: json['id'] as String,
      title: json['title'] as String? ?? json['id'] as String,
      agentId: json['agentId'] as String? ?? 'custom',
      projectId: json['projectId'] as String?,
      deviceId: json['deviceId'] as String?,
      cwd: json['cwd'] as String?,
      worktreePath: json['worktreePath'] as String?,
      model: json['model'] as String?,
      syncState: ThreadSyncState.synced,
      status: _parseStatus(json['status'] as String?),
      lastActivity: updatedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(updatedAt)
          : null,
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null,
    );
  }

  /// Unique thread identifier.
  final String id;

  /// Human readable thread title.
  final String title;

  /// Identifier of the project this thread belongs to, if any.
  final String? projectId;

  /// `macDeviceId` of the paired PC this thread belongs to, if known.
  final String? deviceId;

  /// Working directory of the thread on the PC, if known.
  final String? cwd;

  /// Path of the git worktree backing this thread, if any.
  final String? worktreePath;

  /// Model the thread's agent runs, if known: the **routing id** the agent CLI
  /// expects (`agent/models` `id`), not the readable name — resolve that with
  /// `threadModelLabelProvider` before showing it.
  final String? model;

  /// Local-vs-bridge synchronization state.
  final ThreadSyncState syncState;

  /// High-level thread status.
  final ThreadStatus status;

  /// Timestamp of the last activity in the thread, if any.
  final DateTime? lastActivity;

  /// When the thread was created (bridge `createdAt`), if known. Used to sort
  /// the threads list "newest first" by default.
  final DateTime? createdAt;

  /// Wire identifier of the agent that handles this thread.
  final String agentId;

  /// Returns a copy of this thread with the given fields replaced.
  Thread copyWith({
    String? title,
    String? projectId,
    String? deviceId,
    String? cwd,
    String? worktreePath,
    String? model,
    ThreadSyncState? syncState,
    ThreadStatus? status,
    DateTime? lastActivity,
    DateTime? createdAt,
    String? agentId,
  }) {
    return Thread(
      id: id,
      title: title ?? this.title,
      projectId: projectId ?? this.projectId,
      deviceId: deviceId ?? this.deviceId,
      cwd: cwd ?? this.cwd,
      worktreePath: worktreePath ?? this.worktreePath,
      model: model ?? this.model,
      syncState: syncState ?? this.syncState,
      status: status ?? this.status,
      lastActivity: lastActivity ?? this.lastActivity,
      createdAt: createdAt ?? this.createdAt,
      agentId: agentId ?? this.agentId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        projectId,
        deviceId,
        cwd,
        worktreePath,
        model,
        syncState,
        status,
        lastActivity,
        createdAt,
        agentId,
      ];

  static ThreadStatus _parseStatus(String? name) {
    for (final value in ThreadStatus.values) {
      if (value.name == name) return value;
    }
    return ThreadStatus.active;
  }
}
