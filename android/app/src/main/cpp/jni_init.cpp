#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>

#define LOG_TAG "EasyDictNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// 强制链接 zstd 符号
// 这些符号来自 libzstd.so，通过链接确保库被加载
extern "C" {
    void* ZSTD_createDCtx(void);
    void* ZSTD_createCCtx(void);
    void* ZSTD_createDDict(const void*, size_t);
    void* ZSTD_createCDict(const void*, size_t, int);
    size_t ZSTD_decompress_usingDDict(void*, void*, size_t, const void*, size_t, const void*);
    size_t ZSTD_compress_usingCDict(void*, void*, size_t, const void*, size_t, const void*);
    size_t ZSTD_freeDCtx(void*);
    size_t ZSTD_freeCCtx(void*);
    size_t ZSTD_freeDDict(void*);
    size_t ZSTD_freeCDict(void*);
    unsigned long long ZSTD_getFrameContentSize(const void*, size_t);
    unsigned int ZSTD_isError(size_t);
    const char* ZSTD_getErrorName(size_t);
    size_t ZSTD_decompress(void*, size_t, const void*, size_t);
    size_t ZSTD_compress(void*, size_t, const void*, size_t, int);
    size_t ZSTD_compressBound(size_t);
}

// 存储符号地址，防止编译器优化掉
static volatile void* g_zstd_symbols[] = {
    (void*)ZSTD_createDCtx,
    (void*)ZSTD_createCCtx,
    (void*)ZSTD_createDDict,
    (void*)ZSTD_createCDict,
    (void*)ZSTD_decompress_usingDDict,
    (void*)ZSTD_compress_usingCDict,
    (void*)ZSTD_freeDCtx,
    (void*)ZSTD_freeCCtx,
    (void*)ZSTD_freeDDict,
    (void*)ZSTD_freeCDict,
    (void*)ZSTD_getFrameContentSize,
    (void*)ZSTD_isError,
    (void*)ZSTD_getErrorName,
    (void*)ZSTD_decompress,
    (void*)ZSTD_compress,
    (void*)ZSTD_compressBound,
};

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGI("EasyDict JNI library loaded");
    LOGI("ZSTD_createDCtx address: %p", g_zstd_symbols[0]);
    LOGI("ZSTD_createDDict address: %p", g_zstd_symbols[2]);
    
    // 尝试预加载 libzstd.so
    void* handle = dlopen("libzstd.so", RTLD_NOW | RTLD_GLOBAL);
    if (handle) {
        LOGI("libzstd.so loaded successfully via dlopen");
    } else {
        LOGE("Failed to load libzstd.so: %s", dlerror());
    }
    
    return JNI_VERSION_1_6;
}
