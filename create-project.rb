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
Dir.glob(File.join(root, 'Tingye', '*.swift')).sort.each { |f| app.source_build_phase.add_file_reference(group.new_file(File.basename(f))) }
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
package.repositoryURL = 'https://github.com/weichsel/ZIPFoundation.git'
package.requirement = { 'kind' => 'exactVersion', 'version' => '0.9.20' }
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.product_name = 'ZIPFoundation'; product.package = package; app.package_product_dependencies << product
framework = project.new(Xcodeproj::Project::Object::PBXBuildFile); framework.product_ref = product; app.frameworks_build_phase.files << framework
project.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
end
[app, test, ui_test].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!({ 'SWIFT_VERSION' => '5.0', 'DEVELOPMENT_TEAM' => 'H22S27JV83', 'CODE_SIGN_STYLE' => 'Automatic', 'CURRENT_PROJECT_VERSION' => '110', 'MARKETING_VERSION' => '1.21.0', 'TARGETED_DEVICE_FAMILY' => '1,2', 'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES' })
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
