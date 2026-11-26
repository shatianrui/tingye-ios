require 'xcodeproj'
require 'fileutils'
root = File.expand_path(__dir__)
path = File.join(root, 'Tingye.xcodeproj')
project = Xcodeproj::Project.new(path)
app = project.new_target(:application, 'Tingye', :ios, '17.0')
test = project.new_target(:unit_test_bundle, 'TingyeTests', :ios, '17.0')
test.add_dependency(app)
ui_test = project.new_target(:ui_test_bundle, 'TingyeUITests', :ios, '17.0')
ui_test.add_dependency(app)
group = project.main_group.new_group('Tingye', 'Tingye')
# Preserve nested source groups such as Readium when regenerating the project.
Dir.glob(File.join(root, 'Tingye', '**', '*.swift')).sort.each do |f|
  relative = f.delete_prefix(File.join(root, 'Tingye') + '/')
  parts = relative.split('/')
  parent = parts[0...-1].inject(group) { |g, part| g.groups.find { |child| child.path == part } || g.new_group(part, part) }
  app.source_build_phase.add_file_reference(parent.new_file(parts.last))
end
resources = group.new_group('Resources', 'Resources')
Dir.glob(File.join(root, 'Tingye', 'Resources', '*')).sort.each { |f| app.resources_build_phase.add_file_reference(resources.new_file(File.basename(f))) }
tests = project.main_group.new_group('TingyeTests', 'TingyeTests')
Dir.glob(File.join(root, 'TingyeTests', '*.swift')).sort.each { |f| test.source_build_phase.add_file_reference(tests.new_file(File.basename(f))) }
if Dir.exist?(File.join(root, 'TingyeTests', 'Fixtures'))
  ref = tests.new_file('Fixtures'); ref.last_known_file_type = 'folder'; test.resources_build_phase.add_file_reference(ref)
end
ui_tests = project.main_group.new_group('TingyeUITests', 'TingyeUITests')
Dir.glob(File.join(root, 'TingyeUITests', '*.swift')).sort.each { |f| ui_test.source_build_phase.add_file_reference(ui_tests.new_file(File.basename(f))) }
package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package.repositoryURL = 'https://github.com/readium/ZIPFoundation.git'
package.requirement = { 'kind' => 'exactVersion', 'version' => '3.0.1' }
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.product_name = 'ReadiumZIPFoundation'; product.package = package; app.package_product_dependencies << product
framework = project.new(Xcodeproj::Project::Object::PBXBuildFile); framework.product_ref = product; app.frameworks_build_phase.files << framework
smb_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
smb_package.repositoryURL = 'https://github.com/kishikawakatsumi/SMBClient.git'
smb_package.requirement = { 'kind' => 'exactVersion', 'version' => '0.3.1' }
project.root_object.package_references << smb_package
smb_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
smb_product.product_name = 'SMBClient'; smb_product.package = smb_package; app.package_product_dependencies << smb_product
smb_framework = project.new(Xcodeproj::Project::Object::PBXBuildFile); smb_framework.product_ref = smb_product; app.frameworks_build_phase.files << smb_framework
def link_product(project, target, package, name)
  product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product.product_name = name; product.package = package
  target.package_product_dependencies << product
  build = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build.product_ref = product; target.frameworks_build_phase.files << build
end
readium = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
readium.repositoryURL = 'https://github.com/readium/swift-toolkit.git'
readium.requirement = { 'kind' => 'exactVersion', 'version' => '3.11.1' }
project.root_object.package_references << readium
%w[ReadiumShared ReadiumStreamer ReadiumNavigator].each { |name| link_product(project, app, readium, name) }
link_product(project, test, readium, 'ReadiumShared')
link_product(project, test, readium, 'ReadiumNavigator')
link_product(project, test, package, 'ReadiumZIPFoundation')
soup = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
soup.repositoryURL = 'https://github.com/scinfu/SwiftSoup.git'
soup.requirement = { 'kind' => 'exactVersion', 'version' => '2.13.5' }
project.root_object.package_references << soup
link_product(project, app, soup, 'SwiftSoup')
pow_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pow_package.repositoryURL = 'https://github.com/EmergeTools/Pow.git'
pow_package.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '1.0.6' }
project.root_object.package_references << pow_package
link_product(project, app, pow_package, 'Pow')
# A 档轻量增强（build 153）：摘记富文本渲染 + Markdown 结构化解析。
# app 与 test target 都链接，保证 @testable import Tingye 时模块可解析。
markdown_ui = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
markdown_ui.repositoryURL = 'https://github.com/gonzalezreal/MarkdownUI.git'
markdown_ui.requirement = { 'kind' => 'exactVersion', 'version' => '2.4.1' }
project.root_object.package_references << markdown_ui
link_product(project, app, markdown_ui, 'MarkdownUI')
link_product(project, test, markdown_ui, 'MarkdownUI')
swift_markdown = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
swift_markdown.repositoryURL = 'https://github.com/apple/swift-markdown.git'
swift_markdown.requirement = { 'kind' => 'exactVersion', 'version' => '0.7.1' }
project.root_object.package_references << swift_markdown
link_product(project, app, swift_markdown, 'Markdown')
link_product(project, test, swift_markdown, 'Markdown')
project.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
end
[app, test, ui_test].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!({ 'SWIFT_VERSION' => '5.0', 'DEVELOPMENT_TEAM' => 'H22S27JV83', 'CODE_SIGN_STYLE' => 'Automatic', 'CURRENT_PROJECT_VERSION' => '154', 'MARKETING_VERSION' => '1.26.0', 'TARGETED_DEVICE_FAMILY' => '1,2', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES' })
  end
end
app.build_configurations.each do |config|
  config.build_settings.merge!({ 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.shatianrui.wereader', 'INFOPLIST_FILE' => 'Tingye/Info.plist', 'CODE_SIGN_ENTITLEMENTS' => 'Tingye/Tingye.entitlements', 'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon', 'GENERATE_INFOPLIST_FILE' => 'NO', 'SWIFT_EMIT_LOC_STRINGS' => 'YES', 'SUPPORTS_MACCATALYST' => 'YES', 'CODE_SIGN_ENTITLEMENTS[sdk=macosx*]' => 'Tingye/Tingye-macOS.entitlements', 'ENABLE_PREVIEWS' => 'YES' })
end
test.build_configurations.each do |config|
  config.build_settings.merge!({ 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.shatianrui.wereader.tests', 'GENERATE_INFOPLIST_FILE' => 'YES', 'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/Tingye.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Tingye', 'BUNDLE_LOADER' => '$(TEST_HOST)' })
end
ui_test.build_configurations.each do |config|
  config.build_settings.merge!({ 'PRODUCT_BUNDLE_IDENTIFIER' => 'com.shatianrui.wereader.uitests', 'GENERATE_INFOPLIST_FILE' => 'YES', 'TEST_TARGET_NAME' => 'Tingye' })
end
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app); scheme.add_test_target(test); scheme.add_test_target(ui_test); scheme.set_launch_target(app)
scheme.archive_action.build_configuration = 'Release'
scheme.save_as(path, 'Tingye', true)
project.save
puts path
