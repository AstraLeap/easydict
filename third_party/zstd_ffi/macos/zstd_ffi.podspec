Pod::Spec.new do |s|
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
    '../../zstd/lib/common/*.c',
    '../../zstd/lib/common/*.h',
    '../../zstd/lib/compress/*.c',
    '../../zstd/lib/compress/*.h',
    '../../zstd/lib/decompress/*.c',
    '../../zstd/lib/decompress/*.h',
    '../../zstd/lib/decompress/*.S',
    '../../zstd/lib/dictBuilder/*.c',
    '../../zstd/lib/dictBuilder/*.h',
    '../../zstd/lib/deprecated/*.c',
    '../../zstd/lib/deprecated/*.h',
    '../../zstd/lib/*.h'

  s.public_header_files = '../../zstd/lib/*.h'
  s.header_mappings_dir = '../../zstd/lib'

  s.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ZSTD_STATIC_LINKING_ONLY=1'
  }
end
