#include <stddef.h>
#include <stdint.h>
#include "../../../zstd/lib/zstd.h"

#if defined(__GNUC__)
#define ED_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define ED_EXPORT
#endif

ED_EXPORT ZSTD_DCtx *ED_ZSTD_createDCtx(void) {
  return ZSTD_createDCtx();
}

ED_EXPORT size_t ED_ZSTD_freeDCtx(ZSTD_DCtx *dctx) {
  return ZSTD_freeDCtx(dctx);
}

ED_EXPORT ZSTD_CCtx *ED_ZSTD_createCCtx(void) {
  return ZSTD_createCCtx();
}

ED_EXPORT size_t ED_ZSTD_freeCCtx(ZSTD_CCtx *cctx) {
  return ZSTD_freeCCtx(cctx);
}

ED_EXPORT ZSTD_DDict *ED_ZSTD_createDDict(const void *dictBuffer, size_t dictSize) {
  return ZSTD_createDDict(dictBuffer, dictSize);
}

ED_EXPORT size_t ED_ZSTD_freeDDict(ZSTD_DDict *ddict) {
  return ZSTD_freeDDict(ddict);
}

ED_EXPORT size_t ED_ZSTD_decompress_usingDDict(
    ZSTD_DCtx *dctx,
    void *dst,
    size_t dstCapacity,
    const void *src,
    size_t srcSize,
    const ZSTD_DDict *ddict) {
  return ZSTD_decompress_usingDDict(dctx, dst, dstCapacity, src, srcSize, ddict);
}

ED_EXPORT size_t ED_ZSTD_decompress_usingDict(
    ZSTD_DCtx *dctx,
    void *dst,
    size_t dstCapacity,
    const void *src,
    size_t srcSize,
    const void *dict,
    size_t dictSize) {
  return ZSTD_decompress_usingDict(dctx, dst, dstCapacity, src, srcSize, dict, dictSize);
}

ED_EXPORT ZSTD_CDict *ED_ZSTD_createCDict(const void *dictBuffer, size_t dictSize, int compressionLevel) {
  return ZSTD_createCDict(dictBuffer, dictSize, compressionLevel);
}

ED_EXPORT size_t ED_ZSTD_freeCDict(ZSTD_CDict *cdict) {
  return ZSTD_freeCDict(cdict);
}

ED_EXPORT size_t ED_ZSTD_compress_usingCDict(
    ZSTD_CCtx *cctx,
    void *dst,
    size_t dstCapacity,
    const void *src,
    size_t srcSize,
    const ZSTD_CDict *cdict) {
  return ZSTD_compress_usingCDict(cctx, dst, dstCapacity, src, srcSize, cdict);
}

ED_EXPORT size_t ED_ZSTD_compress_usingDict(
    ZSTD_CCtx *ctx,
    void *dst,
    size_t dstCapacity,
    const void *src,
    size_t srcSize,
    const void *dict,
    size_t dictSize,
    int compressionLevel) {
  return ZSTD_compress_usingDict(
      ctx,
      dst,
      dstCapacity,
      src,
      srcSize,
      dict,
      dictSize,
      compressionLevel);
}

ED_EXPORT size_t ED_ZSTD_compressBound(size_t srcSize) {
  return ZSTD_compressBound(srcSize);
}

ED_EXPORT size_t ED_ZSTD_decompress(
    void *dst,
    size_t dstCapacity,
    const void *src,
    size_t compressedSize) {
  return ZSTD_decompress(dst, dstCapacity, src, compressedSize);
}

ED_EXPORT size_t ED_ZSTD_compress(
    void *dst,
    size_t dstCapacity,
    const void *src,
    size_t srcSize,
    int compressionLevel) {
  return ZSTD_compress(dst, dstCapacity, src, srcSize, compressionLevel);
}

ED_EXPORT unsigned long long ED_ZSTD_getFrameContentSize(const void *src, size_t srcSize) {
  return ZSTD_getFrameContentSize(src, srcSize);
}

ED_EXPORT unsigned ED_ZSTD_isError(size_t code) {
  return ZSTD_isError(code);
}

ED_EXPORT const char *ED_ZSTD_getErrorName(size_t code) {
  return ZSTD_getErrorName(code);
}
