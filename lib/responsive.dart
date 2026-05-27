import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AppDeviceClass { compact, medium, expanded }

class AppBreakpoints {
  const AppBreakpoints._();

  static const double compactMax = 599;
  static const double mediumMax = 1023;
  static const double contentMaxWidth = 1120;
  static const double formMaxWidth = 560;
  static const double readableMaxWidth = 760;
  static const double chatMaxWidth = 900;
}

extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);

  AppDeviceClass get deviceClass {
    final shortestSide = screenSize.shortestSide;
    final width = screenSize.width;

    if (shortestSide < 600 && width < 700) {
      return AppDeviceClass.compact;
    }
    if (width < AppBreakpoints.mediumMax) {
      return AppDeviceClass.medium;
    }
    return AppDeviceClass.expanded;
  }

  bool get isCompact => deviceClass == AppDeviceClass.compact;
  bool get isMedium => deviceClass == AppDeviceClass.medium;
  bool get isExpanded => deviceClass == AppDeviceClass.expanded;

  double get responsiveHorizontalPadding {
    final width = screenSize.width;
    if (width >= 1200) return 40;
    if (width >= 700) return 32;
    return 16;
  }

  EdgeInsets responsivePagePadding({double bottom = 24}) {
    return EdgeInsets.fromLTRB(
      responsiveHorizontalPadding,
      isCompact ? 16 : 24,
      responsiveHorizontalPadding,
      math.max(bottom, MediaQuery.paddingOf(this).bottom + bottom),
    );
  }
}

class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: padding,
        child: child,
      ),
    );
  }
}

class ResponsiveScaffoldBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;

  const ResponsiveScaffoldBody({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.contentMaxWidth,
    this.padding,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: ResponsiveCenter(
        maxWidth: maxWidth,
        padding: padding ?? context.responsivePagePadding(),
        child: child,
      ),
    );

    if (!scrollable) return content;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
    );
  }
}

int responsiveColumnCount(
  BuildContext context, {
  double minTileWidth = 320,
  int maxColumns = 3,
}) {
  final availableWidth = math.min(
    MediaQuery.sizeOf(context).width - context.responsiveHorizontalPadding * 2,
    AppBreakpoints.contentMaxWidth,
  );
  return (availableWidth / minTileWidth)
      .floor()
      .clamp(1, maxColumns)
      .toInt();
}

