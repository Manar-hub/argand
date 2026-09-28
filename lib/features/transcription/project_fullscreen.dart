import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/app_localizations.dart';
import 'media_player_controller.dart';
import 'video_settings_panel.dart';

/// Opens the fullscreen preview, from either mode.
Future<void> showProjectFullscreen(
  BuildContext context, {
  required String projectId,
  required String clipId,
  required VideoPlayerController controller,
}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ProjectFullscreen(
          projectId: projectId,
          clipId: clipId,
          controller: controller,
        ),
      ),
    );

/// The project as it will export, as large as the screen allows.
class ProjectFullscreen extends ConsumerWidget {
  const ProjectFullscreen({
    super.key,
    required this.projectId,
    required this.clipId,
    required this.controller,
  });

  final String projectId;
  final String clipId;
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    void toggle() =>
        ref.read(mediaPlayerProvider(clipId).notifier).togglePlayback();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: toggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.xxl + AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.xxl + AppSpacing.lg,
                    ),
                    child: ProjectStageCanvas(
                      projectId: projectId,
                      clipId: clipId,
                      sourceSize: value.size,
                      picture: VideoPlayer(controller),
                      mediaPositionMs: value.position.inMilliseconds,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: AppSpacing.sm,
                child: Center(
                  child: IconButton(
                    tooltip: value.isPlaying ? l10n.pauseAction : l10n.playAction,
                    iconSize: 36,
                    onPressed: toggle,
                    icon: AppIcon(
                      value.isPlaying ? AppGlyph.pause : AppGlyph.play,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
