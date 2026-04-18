// Common
#include "../../../zstd/lib/common/debug.c"
#include "../../../zstd/lib/common/entropy_common.c"
#include "../../../zstd/lib/common/error_private.c"
#include "../../../zstd/lib/common/fse_decompress.c"
#include "../../../zstd/lib/common/pool.c"
#include "../../../zstd/lib/common/threading.c"
#include "../../../zstd/lib/common/xxhash.c"
#include "../../../zstd/lib/common/zstd_common.c"

// Compress
#include "../../../zstd/lib/compress/fse_compress.c"
#include "../../../zstd/lib/compress/hist.c"
#include "../../../zstd/lib/compress/huf_compress.c"
#include "../../../zstd/lib/compress/zstdmt_compress.c"
#include "../../../zstd/lib/compress/zstd_compress.c"
#include "../../../zstd/lib/compress/zstd_compress_literals.c"
#include "../../../zstd/lib/compress/zstd_compress_sequences.c"
#include "../../../zstd/lib/compress/zstd_compress_superblock.c"
#include "../../../zstd/lib/compress/zstd_double_fast.c"
#include "../../../zstd/lib/compress/zstd_fast.c"
#include "../../../zstd/lib/compress/zstd_lazy.c"
#include "../../../zstd/lib/compress/zstd_ldm.c"
#include "../../../zstd/lib/compress/zstd_opt.c"

// Decompress
#include "../../../zstd/lib/decompress/huf_decompress.c"
#include "../../../zstd/lib/decompress/zstd_ddict.c"
#include "../../../zstd/lib/decompress/zstd_decompress.c"
#include "../../../zstd/lib/decompress/zstd_decompress_block.c"

// Dictionary builder (required for dictionary APIs)
#include "../../../zstd/lib/dictBuilder/cover.c"
#include "../../../zstd/lib/dictBuilder/divsufsort.c"
#include "../../../zstd/lib/dictBuilder/fastcover.c"
#include "../../../zstd/lib/dictBuilder/zdict.c"

// Deprecated compatibility
#include "../../../zstd/lib/deprecated/zbuff_common.c"
#include "../../../zstd/lib/deprecated/zbuff_compress.c"
#include "../../../zstd/lib/deprecated/zbuff_decompress.c"
