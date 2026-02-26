cmake_minimum_required(VERSION 3.22.1)
project("easydict_native")

set(ZSTD_SOURCE_DIR "${CMAKE_SOURCE_DIR}/../../../../../third_party/zstd")

file(GLOB ZSTD_COMMON_SOURCES ${ZSTD_SOURCE_DIR}/lib/common/*.c)
file(GLOB ZSTD_COMPRESS_SOURCES ${ZSTD_SOURCE_DIR}/lib/compress/*.c)
file(GLOB ZSTD_DECOMPRESS_SOURCES ${ZSTD_SOURCE_DIR}/lib/decompress/*.c)
file(GLOB ZSTD_DICTBUILDER_SOURCES ${ZSTD_SOURCE_DIR}/lib/dictBuilder/*.c)
file(GLOB ZSTD_DEPRECATED_SOURCES ${ZSTD_SOURCE_DIR}/lib/deprecated/*.c)

set(ZSTD_SOURCES
    ${ZSTD_COMMON_SOURCES}
    ${ZSTD_COMPRESS_SOURCES}
    ${ZSTD_DECOMPRESS_SOURCES}
    ${ZSTD_DICTBUILDER_SOURCES}
    ${ZSTD_DEPRECATED_SOURCES}
)

add_library(zstd SHARED ${ZSTD_SOURCES})

target_include_directories(zstd PUBLIC
    ${ZSTD_SOURCE_DIR}/lib
    ${ZSTD_SOURCE_DIR}/lib/common
)

target_compile_definitions(zstd PUBLIC 
    ZSTD_STATIC_LINKING_ONLY
    ZSTD_DISABLE_ASM
)

target_compile_options(zstd PRIVATE 
    -O3 
    -fPIC
    -fvisibility=default
)

set_target_properties(zstd PROPERTIES
    C_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
)

# Flutter 会自动加载 libflutter.so，我们需要确保 libzstd.so 被打包到 APK
# 并在应用启动时被加载

# 创建一个简单的 JNI 初始化库，用于强制加载 zstd
add_library(easydict_jni SHARED
    jni_init.cpp
)

target_link_libraries(easydict_jni
    zstd
    log
)

target_compile_options(easydict_jni PRIVATE
    -O3
    -fPIC
)
