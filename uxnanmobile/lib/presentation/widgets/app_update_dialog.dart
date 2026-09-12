import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uxnan/domain/value_objects/app_update_status.dart';
import 'package:uxnan/l10n/app_localizations.dart';
import 'package:uxnan/presentation/providers/app_info_provider.dart';
import 'package:uxnan/presentation/providers/update_providers.dart';
import 'package:uxnan/presentation/theme/icons.dart';
import 'package:uxnan/presentation/theme/spacing.dart';
import 'package:uxnan/presentation/widgets/expressive_progress.dart';
import 'package:uxnan/presentation/widgets/ux_icon.dart';

/// Modal dialog prompting the user when a new app version is available.
///
/// Follows M3 Expressive tokens, showing the version comparison, release notes,
/// and live download progress before offering native installation.
class AppUpdateDialog extends ConsumerWidget {
  /// Creates an [AppUpdateDialog].
  const AppUpdateDialog({super.key});

  static bool _dialogOpen = false;

  /// Shows the dialog if not already showing.
  static Future<void> show(BuildContext context) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AppUpdateDialog(),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final state = ref.watch(appUpdateControllerProvider);
    final controller = ref.read(appUpdateControllerProvider.notifier);

    final info = ref.watch(appPackageInfoProvider);
    final currentVersion = info.maybeWhen(
      data: (i) => i.version,
      orElse: () => '—',
    );
    final targetVersion = state.status?.storeVersion ?? '—';
    final releaseNotes = state.status?.releaseNotes;
    final fileSizeBytes = state.status?.fileSizeBytes;

    return AlertDialog(
      icon: _iconForPhase(state.phase, colors),
      title: Text(_titleForPhase(l10n, state.phase)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildVersionHeader(
              context,
              colors,
              currentVersion: currentVersion,
              targetVersion: targetVersion,
              fileSizeBytes: fileSizeBytes,
            ),
            const SizedBox(height: UxnanSpacing.md),
            _buildContentForPhase(
              context,
              l10n,
              colors,
              state: state,
              targetVersion: targetVersion,
              releaseNotes: releaseNotes,
            ),
          ],
        ),
      ),
      actions: _actionsForPhase(
        context,
        l10n,
        controller: controller,
        state: state,
      ),
    );
  }

  Widget _iconForPhase(AppUpdatePhase phase, ColorScheme colors) {
    switch (phase) {
      case AppUpdatePhase.downloaded:
        return UxIcon(
          UxIcons.checkCircle,
          color: colors.primary,
          size: 28,
        );
      case AppUpdatePhase.error:
        return UxIcon(
          UxIcons.error,
          color: colors.error,
          size: 28,
        );
      case AppUpdatePhase.installing:
        return const PolygonLoader(size: 28);
      case AppUpdatePhase.available:
      case AppUpdatePhase.downloading:
      case AppUpdatePhase.idle:
      case AppUpdatePhase.checking:
      case AppUpdatePhase.upToDate:
        return UxIcon(
          UxIcons.systemUpdate,
          color: colors.primary,
          size: 28,
        );
    }
  }

  String _titleForPhase(AppLocalizations l10n, AppUpdatePhase phase) {
    switch (phase) {
      case AppUpdatePhase.downloading:
        return l10n.updateStatusDownloading;
      case AppUpdatePhase.downloaded:
        return l10n.updateStatusDownloaded;
      case AppUpdatePhase.installing:
        return l10n.updateStatusInstalling;
      case AppUpdatePhase.error:
        return l10n.updateStatusError;
      case AppUpdatePhase.available:
      case AppUpdatePhase.idle:
      case AppUpdatePhase.checking:
      case AppUpdatePhase.upToDate:
        return l10n.updateAvailableTitle;
    }
  }

  Widget _buildVersionHeader(
    BuildContext context,
    ColorScheme colors, {
    required String currentVersion,
    required String targetVersion,
    required int? fileSizeBytes,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UxnanSpacing.md,
        vertical: UxnanSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(UxnanRadius.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _VersionChip(
            label: 'v$currentVersion',
            background: colors.surfaceContainer,
            textColor: colors.onSurfaceVariant,
          ),
          const SizedBox(width: UxnanSpacing.xs),
          UxIcon(
            UxIcons.chevronRight,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: UxnanSpacing.xs),
          _VersionChip(
            label: 'v$targetVersion',
            background: colors.primaryContainer,
            textColor: colors.onPrimaryContainer,
            isBold: true,
          ),
          if (fileSizeBytes != null && fileSizeBytes > 0) ...[
            const Spacer(),
            Text(
              _formatBytes(fileSizeBytes),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContentForPhase(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colors, {
    required AppUpdateState state,
    required String targetVersion,
    required String? releaseNotes,
  }) {
    switch (state.phase) {
      case AppUpdatePhase.downloading:
        final fraction = state.install?.fraction;
        final percentText = fraction != null
            ? '${(fraction * 100).round()}%'
            : l10n.updateStatusDownloading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(UxnanRadius.sm),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: UxnanSpacing.sm),
            Text(
              percentText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        );
      case AppUpdatePhase.downloaded:
        return Text(
          l10n.updateStatusDownloaded,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        );
      case AppUpdatePhase.installing:
        return Text(
          l10n.updateStatusInstalling,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        );
      case AppUpdatePhase.error:
        return Text(
          state.errorMessage ?? l10n.updateStatusError,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.error,
              ),
          textAlign: TextAlign.center,
        );
      case AppUpdatePhase.available:
      case AppUpdatePhase.idle:
      case AppUpdatePhase.checking:
      case AppUpdatePhase.upToDate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (releaseNotes != null && releaseNotes.isNotEmpty) ...[
              Text(
                l10n.updateWhatsNewLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: UxnanSpacing.xs),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(UxnanSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: const BorderRadius.all(UxnanRadius.sm),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ] else
              Text(
                l10n.updateAvailableBodyVersion(targetVersion),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        );
    }
  }

  List<Widget> _actionsForPhase(
    BuildContext context,
    AppLocalizations l10n, {
    required AppUpdateController controller,
    required AppUpdateState state,
  }) {
    switch (state.phase) {
      case AppUpdatePhase.downloading:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.updateDialogBackgroundAction),
          ),
        ];
      case AppUpdatePhase.downloaded:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.updateDialogLaterAction),
          ),
          FilledButton(
            onPressed: controller.install,
            child: Text(l10n.updateInstallAction),
          ),
        ];
      case AppUpdatePhase.installing:
        return const [];
      case AppUpdatePhase.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionDismiss),
          ),
          FilledButton(
            onPressed: controller.download,
            child: Text(l10n.actionRetry),
          ),
        ];
      case AppUpdatePhase.available:
      case AppUpdatePhase.idle:
      case AppUpdatePhase.checking:
      case AppUpdatePhase.upToDate:
        final isIos = state.status?.channel == UpdateChannel.appStore;
        return [
          TextButton(
            onPressed: () {
              controller.dismiss();
              Navigator.of(context).pop();
            },
            child: Text(l10n.updateDialogIgnoreVersion),
          ),
          TextButton(
            onPressed: () {
              controller.dismissDialog();
              Navigator.of(context).pop();
            },
            child: Text(l10n.updateDialogLaterAction),
          ),
          FilledButton(
            onPressed: state.starting ? null : controller.download,
            child: Text(
              isIos ? l10n.updateAction : l10n.updateDownloadAction,
            ),
          ),
        ];
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.label,
    required this.background,
    required this.textColor,
    this.isBold = false,
  });

  final String label;
  final Color background;
  final Color textColor;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UxnanSpacing.xs,
        vertical: 2,
      ),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(UxnanRadius.sm),
      ).copyWith(color: background),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
      ),
    );
  }
}
