Pod::Spec.new do |s|
  plugin_macos_dir = File.realpath(__dir__)
  zstd_root = File.expand_path('../../zstd', plugin_macos_dir)

  s.name             = 'zstd_ffi'
  s.version          = '0.0.1'
  s.summary          = 'Zstandard compression library for FFI'
  s.description      = 'Zstandard is a fast lossless compression algorithm'
  s.homepage         = 'https://github.com/facebook/zstd'
  s.license          = { :type => 'BSD', :file => '../../zstd/LICENSE' }
  s.author           = { 'Facebook' => 'zstd@fb.com' }
  s.source           = { :path => '.' }

  s.source_files =
    'Classes/**/*',
    "#{zstd_root}/lib/common/*.c",
    "#{zstd_root}/lib/common/*.h",
    "#{zstd_root}/lib/compress/*.c",
    "#{zstd_root}/lib/compress/*.h",
    "#{zstd_root}/lib/decompress/*.c",
    "#{zstd_root}/lib/decompress/*.h",
    "#{zstd_root}/lib/decompress/*.S",
    "#{zstd_root}/lib/dictBuilder/*.c",
    "#{zstd_root}/lib/dictBuilder/*.h",
    "#{zstd_root}/lib/deprecated/*.c",
    "#{zstd_root}/lib/deprecated/*.h",
    "#{zstd_root}/lib/*.h"

  s.public_header_files = "#{zstd_root}/lib/*.h"
  s.header_mappings_dir = "#{zstd_root}/lib"

  s.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ZSTD_STATIC_LINKING_ONLY=1',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
    'DEAD_CODE_STRIPPING' => 'NO',
    'HEADER_SEARCH_PATHS' => "$(inherited) \"#{zstd_root}/lib\" \"#{zstd_root}/lib/common\"",
    'OTHER_CFLAGS' => '$(inherited) -fvisibility=default'
  }
end
