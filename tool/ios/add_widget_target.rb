# Adds the live_timer_widget WidgetKit extension to a Flutter app's Xcode
# project. Run by `dart run live_timer_widget:setup_ios`, which first copies
# the template files into ios/<target>/.
#
#   ruby add_widget_target.rb <ios/Runner.xcodeproj> <target> <app group> <deployment target>
#
# Safe to run again: every step checks what is already there.

require 'xcodeproj'

project_path, target_name, app_group, deployment_target = ARGV
abort 'usage: add_widget_target.rb <xcodeproj> <target> <app group> <deployment target>' if app_group.nil?
deployment_target ||= '15.0'

ios_dir = File.dirname(project_path)
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'No Runner target'

def say(message)
  puts "  • #{message}"
end

# Adds app_group to the entitlements plist at path, creating it if needed.
def add_app_group(path, app_group)
  plist = File.exist?(path) ? Xcodeproj::Plist.read_from_path(path) : {}
  groups = plist['com.apple.security.application-groups'] ||= []
  return false if groups.include?(app_group)

  groups << app_group
  Xcodeproj::Plist.write_to_path(plist, path)
  true
end

def file_in(group, name)
  group.files.find { |f| f.path == name } || group.new_reference(name)
end

# 1. The App Group on Runner -------------------------------------------------

runner_group = project.main_group['Runner'] || project.main_group
runner.build_configurations.each do |config|
  entitlements = config.build_settings['CODE_SIGN_ENTITLEMENTS'] || 'Runner/Runner.entitlements'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = entitlements
  path = File.join(ios_dir, entitlements)
  say "App Group #{app_group} added to #{entitlements}" if add_app_group(path, app_group)
  if entitlements.start_with?('Runner/')
    file_in(runner_group, File.basename(entitlements))
  end
end

# 2. The extension target ----------------------------------------------------

target = project.targets.find { |t| t.name == target_name }
if target.nil?
  target = project.new_target(:app_extension, target_name, :ios, deployment_target, nil, :swift)
  say "Created target #{target_name}"
end

group = project.main_group[target_name] || project.main_group.new_group(target_name, target_name)
swift = file_in(group, 'LiveTimerWidget.swift')
target.source_build_phase.add_file_reference(swift, true)
file_in(group, 'Info.plist')
file_in(group, "#{target_name}.entitlements")
xcconfig = file_in(group, "#{target_name}.xcconfig")
target.add_system_framework(%w[WidgetKit SwiftUI])

# Flutter apps have a Profile configuration that new_target doesn't create.
project.build_configurations.each do |project_config|
  next if target.build_configurations.any? { |c| c.name == project_config.name }

  target.add_build_configuration(project_config.name, project_config.name == 'Debug' ? :debug : :release)
end

runner_settings = runner.build_configurations.to_h { |c| [c.name, c.build_settings] }
target.build_configurations.each do |config|
  app = runner_settings[config.name] || runner_settings['Release'] || {}
  bundle_id = app['PRODUCT_BUNDLE_IDENTIFIER'] || '$(PRODUCT_BUNDLE_IDENTIFIER)'
  config.base_configuration_reference = xcconfig
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => "#{bundle_id}.#{target_name}",
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'INFOPLIST_FILE' => "#{target_name}/Info.plist",
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'CODE_SIGN_ENTITLEMENTS' => "#{target_name}/#{target_name}.entitlements",
    'IPHONEOS_DEPLOYMENT_TARGET' => deployment_target,
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'SKIP_INSTALL' => 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  )
  %w[DEVELOPMENT_TEAM CODE_SIGN_STYLE CODE_SIGN_IDENTITY].each do |key|
    config.build_settings[key] = app[key] if app[key]
  end
end

# 3. Embed it in the app -----------------------------------------------------

embed = runner.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '13' }
if embed.nil?
  embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
  embed.symbol_dst_subfolder_spec = :plug_ins
end
unless embed.files_references.include?(target.product_reference)
  file = embed.add_file_reference(target.product_reference, true)
  file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  say "Embedded #{target_name}.appex in Runner"
end

# Flutter's "Thin Binary" script reads the built app; embedding after it makes
# Xcode report a dependency cycle.
phases = runner.build_phases
thin = phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin && phases.index(embed) > phases.index(thin)
  phases.delete(embed)
  phases.insert(phases.index(thin), embed)
end

runner.add_dependency(target) unless runner.dependencies.any? { |d| d.target == target }

project.save
say "Saved #{project_path}"
