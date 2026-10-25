/// Shared UI building blocks for the Sible Miner design system.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';

/// Card with subtle gradient + hairline border ("glass" look).
class GlowCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;
  final VoidCallback? onTap;

  const GlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient ?? SibleTheme.cardGradient,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: SibleTheme.border),
              boxShadow: [
                BoxShadow(
                  color: SibleTheme.primary.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Big hero stat used on the dashboard.
class HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  final Color? tint;

  const HeroStat({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    required this.icon,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return GlowCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          (tint ?? SibleTheme.primary).withValues(alpha: 0.25),
          SibleTheme.surface,
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint ?? SibleTheme.cyan),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: SibleTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: SibleTheme.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  height: 1.0,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    suffix!,
                    style: const TextStyle(
                      color: SibleTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Small KPI tile.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = SibleTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SibleTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SibleTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: SibleTheme.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: SibleTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Account/proxy status pill.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool dot;

  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dot = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

Color statusColor(AccountStatus s) {
  switch (s) {
    case AccountStatus.mining:
      return SibleTheme.success;
    case AccountStatus.claiming:
      return SibleTheme.cyan;
    case AccountStatus.idle:
    case AccountStatus.newAccount:
      return SibleTheme.textSecondary;
    case AccountStatus.needsOtp:
    case AccountStatus.needsRelogin:
      return SibleTheme.warning;
    case AccountStatus.error:
      return SibleTheme.danger;
    case AccountStatus.banned:
      return SibleTheme.danger;
    case AccountStatus.disabled:
      return SibleTheme.textSecondary;
  }
}

String statusLabel(AccountStatus s) {
  switch (s) {
    case AccountStatus.newAccount:
      return 'NEW';
    case AccountStatus.mining:
      return 'MINING';
    case AccountStatus.claiming:
      return 'CLAIMING';
    case AccountStatus.idle:
      return 'IDLE';
    case AccountStatus.needsOtp:
      return 'NEEDS OTP';
    case AccountStatus.needsRelogin:
      return 'RE-LOGIN';
    case AccountStatus.error:
      return 'ERROR';
    case AccountStatus.banned:
      return 'BANNED';
    case AccountStatus.disabled:
      return 'OFF';
  }
}

/// Section header with optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Empty state placeholder.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: SibleTheme.surfaceHigh,
                shape: BoxShape.circle,
                border: Border.all(color: SibleTheme.border),
              ),
              child: Icon(icon, size: 30, color: SibleTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SibleTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SibleTheme.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// Single activity log row.
class LogTile extends StatelessWidget {
  final LogEvent event;

  const LogTile({super.key, required this.event});

  Color get _color {
    switch (event.level) {
      case LogLevel.success:
        return SibleTheme.success;
      case LogLevel.warn:
        return SibleTheme.warning;
      case LogLevel.error:
        return SibleTheme.danger;
      default:
        return SibleTheme.cyan;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SibleTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SibleTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.category.toUpperCase(),
                      style: TextStyle(
                        color: _color,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeAgo(event.ts),
                      style: const TextStyle(
                        color: SibleTheme.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  event.message,
                  style: const TextStyle(
                    color: SibleTheme.textPrimary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                if (event.accountLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      event.accountLabel,
                      style: const TextStyle(
                        color: SibleTheme.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient primary button.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: SibleTheme.brandGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: SibleTheme.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
