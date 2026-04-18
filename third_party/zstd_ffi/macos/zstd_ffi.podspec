Pod::Spec.new do |s|
  zstd_roots = [
    '../../zstd',
    '../../../../../../../third_party/zstd',
  ]

  zstd_globs = [
    'lib/common/*.c',
    'lib/common/*.h',
    'lib/compress/*.c',
    'lib/compress/*.h',
    'lib/decompress/*.c',
    'lib/decompress/*.h',
    'lib/decompress/*.S',
    'lib/dictBuilder/*.c',
    'lib/dictBuilder/*.h',
    'lib/deprecated/*.c',
    'lib/deprecated/*.h',
    'lib/*.h',
  ]

  license_path = (
    zstd_roots
      .map { |root| "#{root}/LICENSE" }
      .find { |p| File.exist?(File.expand_path(p, __dir__)) } ||
    '../../zstd/LICENSE'
  )

  s.name             = 'zstd_ffi'
  s.version          = '0.0.1'
  s.summary          = 'Zstandard compression library for FFI'
  s.description      = 'Zstandard is a fast lossless compression algorithm'
  s.homepage         = 'https://github.com/facebook/zstd'
  s.license          = { :type => 'BSD', :file => license_path }
  s.author           = { 'Facebook' => 'zstd@fb.com' }
  s.source           = { :path => '.' }

  s.source_files = ['Classes/**/*'] + zstd_roots.flat_map { |root|
    zstd_globs.map { |glob| "#{root}/#{glob}" }
  }

  s.public_header_files = zstd_roots.map { |root| "#{root}/lib/*.h" }

  s.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'ZSTD_STATIC_LINKING_ONLY=1',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO',
    'DEAD_CODE_STRIPPING' => 'NO',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../../zstd/lib" "${PODS_TARGET_SRCROOT}/../../zstd/lib/common" "${PODS_TARGET_SRCROOT}/../../../../../../../third_party/zstd/lib" "${PODS_TARGET_SRCROOT}/../../../../../../../third_party/zstd/lib/common"',
    'OTHER_CFLAGS' => '$(inherited) -fvisibility=default'
  }
end
