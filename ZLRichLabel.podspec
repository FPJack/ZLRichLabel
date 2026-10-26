#
# Be sure to run `pod lib lint ZLRichLabel.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'ZLRichLabel'
  s.version          = '3.0.0'
  s.summary          = 'Regex-rule based rich text label with <h> tag highlighting, tappable spans, inline images and custom views.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
ZLRichLabel is a CoreText based rich text label (no third-party dependency).
ZLRichLabel (base class) parses text with prioritized regex rules and lets you render each match
(attributes, replaced text, images, inline custom views, tap handling, pressed highlight).
ZLTagRichLabel adds built-in <h>/<h1>/<h2>... tag highlighting with per-tag styles and tap handlers.
Supports multi-line truncation, Auto Layout self-sizing, RTL text and Objective-C.
                       DESC

  s.homepage         = 'https://github.com/FPJack/ZLRichLabel.git'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'fanpeng' => '25514129393@qq.com' }
  s.source           = { :git => 'https://github.com/FPJack/ZLRichLabel.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  s.frameworks = 'UIKit', 'CoreText'
  s.source_files = 'ZLRichLabel/Classes/**/*'
  
  # s.resource_bundles = {
  #   'ZLRichLabel' => ['ZLRichLabel/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'

end
