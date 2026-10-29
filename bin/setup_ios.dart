// Adds the live_timer_widget WidgetKit extension to the Flutter app in the
// current directory:
//
//   dart run live_timer_widget:setup_ios --app-group group.com.example.app
//
// It copies the widget template into ios/<target>/, then has
// tool/ios/add_widget_target.rb (the `xcodeproj` gem, which CocoaPods
// installs) add the target, embed it in Runner and give both the App Group.

import 'dart:io';
import 'dart:isolate';

const _usage = '''
Adds the live_timer_widget extension to ios/Runner.xcodeproj.

Usage: dart run live_timer_widget:setup_ios --app-group <group.id> [options]

  --app-group <id>        App Group shared by the app and the widget (required).
                          Pass the same id to LiveTimerWidget.initialize.
  --target <name>         Extension target name. Default: LiveTimerWidget
  --kind <kind>           WidgetKit kind; pass it as iOSWidgetKind if changed.
                          Default: LiveTimerWidget
  --display-name <name>   Name in the widget gallery. Default: Timer
  --description <text>    Description in the widget gallery.
  --deployment-target <v> Minimum iOS for the extension. Default: 15.0
  --force                 Overwrite template files you've edited.
  -h, --help              Show this help.
''';

Future<void> main(List<String> args) async {
  final options = _parse(args);
  if (options == null || options.containsKey('help')) {
    stdout.write(_usage);
    exit(options == null ? 64 : 0);
  }

  final appGroup = options['app-group'];
  if (appGroup == null || !appGroup.startsWith('group.')) {
    stderr.writeln('--app-group is required and must start with "group.".\n');
    stdout.write(_usage);
    exit(64);
  }
  final target = options['target'] ?? 'LiveTimerWidget';
  final force = options.containsKey('force');
  final replacements = {
    '{{APP_GROUP_ID}}': appGroup,
    '{{KIND}}': options['kind'] ?? 'LiveTimerWidget',
    '{{DISPLAY_NAME}}': options['display-name'] ?? 'Timer',
    '{{DESCRIPTION}}':
        options['description'] ??
        'A live timer that keeps running with the app closed.',
  };

  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!project.existsSync()) {
    _fail(
      'No ios/Runner.xcodeproj here. Run this from your Flutter app\'s root.',
    );
  }

  final packageRoot = await _packageRoot();
  final template = Directory('$packageRoot/tool/ios/template');
  final destination = Directory('ios/$target')..createSync(recursive: true);

  stdout.writeln('Setting up the $target widget extension:');
  final files = {
    'LiveTimerWidget.swift': 'LiveTimerWidget.swift',
    'Info.plist': 'Info.plist',
    'Widget.entitlements': '$target.entitlements',
    'Widget.xcconfig': '$target.xcconfig',
  };
  for (final MapEntry(key: source, value: name) in files.entries) {
    final out = File('${destination.path}/$name');
    if (out.existsSync() && !force) {
      stdout.writeln('  • Kept ios/$target/$name (--force to overwrite)');
      continue;
    }
    var content = File('${template.path}/$source').readAsStringSync();
    replacements.forEach(
      (from, to) => content = content.replaceAll(from, _escape(to, name)),
    );
    out.writeAsStringSync(content);
    stdout.writeln('  • Wrote ios/$target/$name');
  }

  final ruby = await Process.run('ruby', [
    '$packageRoot/tool/ios/add_widget_target.rb',
    'ios/Runner.xcodeproj',
    target,
    appGroup,
    options['deployment-target'] ?? '15.0',
  ]);
  stdout.write(ruby.stdout);
  if (ruby.exitCode != 0) {
    stderr.write(ruby.stderr);
    if ('${ruby.stderr}'.contains('xcodeproj')) {
      stderr.writeln('\nThe xcodeproj gem is missing: gem install xcodeproj');
    }
    exit(ruby.exitCode);
  }

  stdout.writeln('''

Done. Next:
  1. In main(): await LiveTimerWidget.initialize(iOSAppGroupId: '$appGroup');
  2. Open ios/Runner.xcworkspace once and check Signing & Capabilities of both
     Runner and $target: same team, App Group "$appGroup" ticked.
  3. Build. The widget is in the home screen gallery as "${replacements['{{DISPLAY_NAME}}']}".
''');
}

/// `--key value`, `--key=value` and bare `--flag`s; null on a stray argument.
Map<String, String>? _parse(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') return {'help': ''};
    if (!arg.startsWith('--')) return null;
    final body = arg.substring(2);
    final eq = body.indexOf('=');
    if (eq != -1) {
      options[body.substring(0, eq)] = body.substring(eq + 1);
    } else if (body == 'force') {
      options[body] = '';
    } else if (i + 1 < args.length) {
      options[body] = args[++i];
    } else {
      return null;
    }
  }
  return options;
}

/// Escapes a value for the file it lands in: a Swift string or a plist.
String _escape(String value, String fileName) {
  if (fileName.endsWith('.swift')) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

Future<String> _packageRoot() async {
  final lib = await Isolate.resolvePackageUri(
    Uri.parse('package:live_timer_widget/live_timer_widget.dart'),
  );
  if (lib == null) _fail('Could not locate the live_timer_widget package.');
  return File.fromUri(lib).parent.parent.path;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
