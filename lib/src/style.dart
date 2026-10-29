import 'package:flutter/material.dart';

import 'widget_image.dart';

/// The widget's colors. The widget sits on the home screen, not inside the
/// app, so it keeps one palette whatever the system theme is — pick colors
/// that read on [background] and on any photo you put behind the text.
class LiveTimerStyle {
  const LiveTimerStyle({
    this.background = const Color(0xFF1B1530),
    this.backgroundEnd,
    this.foreground = const Color(0xFFFFFFFF),
    this.muted = const Color(0xCCFFFFFF),
    this.accent = const Color(0xFF8AC443),
    this.onAccent = const Color(0xFF14101F),
    this.track = const Color(0x38FFFFFF),
    this.imageScrim = true,
  });

  /// A style built from the app's theme, so the widget matches it.
  factory LiveTimerStyle.fromColorScheme(ColorScheme scheme) => LiveTimerStyle(
    background: scheme.primary,
    backgroundEnd: Color.lerp(scheme.primary, Colors.black, 0.35),
    foreground: scheme.onPrimary,
    muted: scheme.onPrimary.withValues(alpha: 0.8),
    accent: scheme.secondary,
    onAccent: scheme.onSecondary,
    track: scheme.onPrimary.withValues(alpha: 0.22),
  );

  /// Fills the widget; with [backgroundEnd], the start of a diagonal gradient.
  final Color background;
  final Color? backgroundEnd;

  /// The clock and titles.
  final Color foreground;

  /// Subtitles and secondary labels.
  final Color muted;

  /// The progress bar, the percentage and the idle action button.
  final Color accent;

  /// Text on the [accent] button.
  final Color onAccent;

  /// The unfilled part of the progress bar.
  final Color track;

  /// Whether a background photo is faded into [background] on the text side
  /// and at the bottom, so the text stays readable over any photo.
  final bool imageScrim;

  Map<String, Object?> toJson() => {
    'background': background.toARGB32(),
    'backgroundEnd': backgroundEnd?.toARGB32(),
    'foreground': foreground.toARGB32(),
    'muted': muted.toARGB32(),
    'accent': accent.toARGB32(),
    'onAccent': onAccent.toARGB32(),
    'track': track.toARGB32(),
    'imageScrim': imageScrim,
  };
}

/// What the widget shows when no timer is running.
///
/// Until the app sets it, the widget shows the platform's default texts
/// (`ltw_idle_title` / `ltw_idle_subtitle` string resources on Android, the
/// template's strings on iOS).
class LiveTimerIdle {
  const LiveTimerIdle({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.image,
    this.link,
    this.actionLink,
  });

  final String title;

  /// Shown on medium and larger widgets.
  final String? subtitle;

  /// A button label, e.g. "Start". No button without it.
  final String? actionLabel;

  final WidgetImage? image;

  /// Passed back in [LiveTimerTap.link] when the widget is tapped.
  final Uri? link;

  /// Passed back when the action button is tapped; [link] if `null`.
  ///
  /// iOS small widgets and lock-screen widgets are a single tap target, so
  /// there a tap always reports [link].
  final Uri? actionLink;

  Map<String, Object?> toJson(String? Function(WidgetImage?) imageName) => {
    'title': title,
    'subtitle': subtitle,
    'actionLabel': actionLabel,
    'image': imageName(image),
    'link': link?.toString(),
    'actionLink': actionLink?.toString(),
  };
}
