cmake_minimum_required(VERSION 3.22.1)
project("zstd")

# zstd 源码路径
set(ZSTD_SOURCE_DIR "${CMAKE_SOURCE_DIR}/../../../../../third_party/zstd")

# 收集 zstd 源文件
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

# 创建 zstd 静态库
add_library(zstd STATIC ${ZSTD_SOURCES})

target_include_directories(zstd PUBLIC
    ${ZSTD_SOURCE_DIR}/lib
    ${ZSTD_SOURCE_DIR}/lib/common
)

# 定义 ZSTD_STATIC_LINKING_ONLY 以支持字典功能
target_compile_definitions(zstd PUBLIC ZSTD_STATIC_LINKING_ONLY)

# 设置编译选项
target_compile_options(zstd PRIVATE -O3 -fPIC)
