Pod::Spec.new do |s|
  s.name             = 'zstd_ffi'
  s.version          = '0.0.1'
  s.summary          = 'Zstandard compression library for FFI'
  s.description      = 'Zstandard is a fast lossless compression algorithm'
  s.homepage         = 'https://github.com/facebook/zstd'
  s.license          = { :type => 'BSD', :file => '../../zstd/LICENSE' }
  s.author           = { 'Facebook' => 'zstd@fb.com' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'

  s.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ZSTD_STATIC_LINKING_ONLY=1 ZDICT_STATIC_LINKING_ONLY=1 ZSTD_DISABLE_ASM=1',
    'CLANG_ENABLE_MODULES' => 'NO',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
    'DEAD_CODE_STRIPPING' => 'NO',
    'OTHER_CFLAGS' => '$(inherited) -fvisibility=default'
  }
end
