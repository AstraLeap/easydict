Pod::Spec.new do |s|
  s.name             = 'zstd'
  s.version          = '1.5.6'
  s.summary          = 'Zstandard compression library'
  s.description      = 'Zstandard is a fast lossless compression algorithm'
  s.homepage         = 'https://github.com/facebook/zstd'
  s.license          = { :type => 'BSD', :file => '../third_party/zstd/LICENSE' }
  s.author           = { 'Facebook' => 'zstd@fb.com' }
  s.source           = { :path => '../third_party/zstd' }

  s.source_files = 
    '../third_party/zstd/lib/common/*.c',
    '../third_party/zstd/lib/common/*.h',
    '../third_party/zstd/lib/compress/*.c',
    '../third_party/zstd/lib/compress/*.h',
    '../third_party/zstd/lib/decompress/*.c',
    '../third_party/zstd/lib/decompress/*.h',
    '../third_party/zstd/lib/dictBuilder/*.c',
    '../third_party/zstd/lib/dictBuilder/*.h',
    '../third_party/zstd/lib/deprecated/*.c',
    '../third_party/zstd/lib/deprecated/*.h',
    '../third_party/zstd/lib/*.h'

  s.public_header_files = '../third_party/zstd/lib/*.h'
  s.header_mappings_dir = '../third_party/zstd/lib'

  s.osx.deployment_target = '10.14'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ZSTD_STATIC_LINKING_ONLY=1'
  }
end
