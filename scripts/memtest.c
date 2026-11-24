/* 内存压力测试：分配大块内存，写入模式后逐字节校验。
 * 比对失败 = 内存位翻转，是内存不稳定的直接证据。
 *
 * 编译: clang -O2 -o memtest memtest.c
 * 运行: ./memtest [GB] [rounds]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static int test_pattern(unsigned char *buf, size_t size, unsigned char pat, const char *name)
{
    size_t i;
    size_t bad = 0, first = (size_t)-1;

    /* 填充 */
    for (i = 0; i < size; i += 8) {
        *(uint64_t *)(buf + i) = ((uint64_t)pat << 56) | ((uint64_t)pat << 48) |
                                 ((uint64_t)pat << 40) | ((uint64_t)pat << 32) |
                                 ((uint64_t)pat << 24) | ((uint64_t)pat << 16) |
                                 ((uint64_t)pat << 8)  |  (uint64_t)pat;
    }

    /* 读回校验 */
    for (i = 0; i < size; i++) {
        if (buf[i] != pat) {
            if (first == (size_t)-1) first = i;
            bad++;
            if (bad > 1000000) break;
        }
    }

    if (bad) {
        printf("  [FAIL] pattern 0x%02X: %zu bad bytes, first at offset %zu (got 0x%02X)\n",
               pat, bad, first, buf[first]);
        return 1;
    }
    printf("  [ OK ] pattern 0x%02X  (%.1f GB)\n", pat, size / 1073741824.0);
    return 0;
}

int main(int argc, char **argv)
{
    unsigned long gb = (argc > 1) ? strtoul(argv[1], NULL, 10) : 4;
    int rounds = (argc > 2) ? atoi(argv[2]) : 3;
    size_t size = gb * 1073741824ULL;
    unsigned char *buf;
    int errors = 0, r;

    printf("memtest: %.0f GB per round, %d rounds\n", size / 1073741824.0, rounds);
    fflush(stdout);

    buf = (unsigned char *)malloc(size);
    if (!buf) {
        printf("malloc failed for %zu bytes\n", size);
        return 2;
    }

    /* 先触碰所有页，确保物理内存真正分配 */
    memset(buf, 0, size);

    for (r = 0; r < rounds; r++) {
        printf("\n=== round %d/%d ===\n", r + 1, rounds);
        fflush(stdout);
        errors += test_pattern(buf, size, 0xA5, "A5");
        errors += test_pattern(buf, size, 0x5A, "5A");
        errors += test_pattern(buf, size, 0xFF, "FF");
        errors += test_pattern(buf, size, 0x00, "00");
    }

    free(buf);
    printf("\n=== result ===\nerrors: %d\n", errors);
    if (errors == 0)
        printf("PASS: no memory errors detected\n");
    else
        printf("FAIL: memory errors detected!\n");
    return errors ? 1 : 0;
}
