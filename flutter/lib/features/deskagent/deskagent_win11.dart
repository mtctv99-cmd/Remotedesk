import 'package:flutter/material.dart';

import 'deskagent_tokens.dart';

/// Reusable Fluent/Win11 controls for DeskAgent surfaces.
/// All colors/metrics come from [DeskAgentFluentColors] / [DeskAgentMetrics],
/// which were copied from the approved mockups — no new values invented here.

/// 26px icon-only Fluent button: 4px radius, white 6%/10% hover/active.
class Win11IconButton extends StatelessWidget {
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  const Win11IconButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 26,
        height: 26,
        child: Material(
          color: active
              ? DeskAgentFluentColors.accent.withOpacity(0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
          child: InkWell(
            borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusButton),
            hoverColor: DeskAgentFluentColors.hoverOverlay,
            splashColor: DeskAgentFluentColors.activeOverlay,
            onTap: onPressed,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}

/// Native caption button: 46x32, close turns Win11 red on hover.
class Win11CaptionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  const Win11CaptionButton({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 46,
        height: DeskAgentMetrics.titlebarHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            hoverColor: isClose
                ? DeskAgentFluentColors.closeHover
                : DeskAgentFluentColors.hoverOverlay,
            child: Icon(icon,
                size: 14, color: DeskAgentFluentColors.titlebarTextSecondary),
          ),
        ),
      ),
    );
  }
}

/// Fluent card: #272727 surface, 8% border, 8px radius.
class Win11Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const Win11Card({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? DeskAgentFluentColors.card,
        borderRadius: BorderRadius.circular(DeskAgentMetrics.radiusCard),
        border: Border.all(color: DeskAgentFluentColors.border8),
      ),
      child: child,
    );
  }
}
