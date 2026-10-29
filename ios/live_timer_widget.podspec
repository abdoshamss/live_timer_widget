#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint live_timer_widget.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'live_timer_widget'
  s.version          = '0.1.0'
  s.summary          = 'Live home and lock screen timer widgets for Flutter.'
  s.description      = <<-DESC
Live home and lock screen timer widgets, driven from Dart.
                       DESC
  s.homepage         = 'https://github.com/abdoshamss/live_timer_widget'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Abdo Shamss' => 'abdoshams2005@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'live_timer_widget/Sources/live_timer_widget/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'live_timer_widget_privacy' => ['live_timer_widget/Sources/live_timer_widget/PrivacyInfo.xcprivacy']}
end
