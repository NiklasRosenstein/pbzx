/**
 * Unit tests for pbzx static functions.
 * Uses greatest.h single-header test framework.
 * Compiled with -DTESTING to exclude main() from pbzx.c.
 */

#include <stdint.h>
#include <unistd.h>

#include "greatest.h"

/* Include the source directly to access static functions. */
#include "../pbzx.c"

/* ========== min() tests ========== */

TEST test_min_first_smaller(void) {
    ASSERT_EQ(3, min(3, 5));
    PASS();
}

TEST test_min_second_smaller(void) {
    ASSERT_EQ(3, min(5, 3));
    PASS();
}

TEST test_min_equal(void) {
    ASSERT_EQ(0, min(0, 0));
    ASSERT_EQ(42, min(42, 42));
    PASS();
}

TEST test_min_uint32_max(void) {
    ASSERT_EQ(0, min(UINT32_MAX, 0));
    ASSERT_EQ(0, min(0, UINT32_MAX));
    PASS();
}

SUITE(suite_min) {
    RUN_TEST(test_min_first_smaller);
    RUN_TEST(test_min_second_smaller);
    RUN_TEST(test_min_equal);
    RUN_TEST(test_min_uint32_max);
}

/* ========== stream_init() tests ========== */

TEST test_stream_init_zeros_fields(void) {
    struct stream s;
    s.type = 99;
    s.xar = (xar_t)(uintptr_t)0xdeadbeef;
    s.fp = (FILE*)(uintptr_t)0xdeadbeef;
    stream_init(&s);
    ASSERT_EQ(0, s.type);
    ASSERT_EQ(NULL, s.xar);
    ASSERT_EQ(NULL, s.fp);
    PASS();
}

SUITE(suite_stream_init) {
    RUN_TEST(test_stream_init_zeros_fields);
}

/* ========== stream_open() / stream_close() tests ========== */

TEST test_stream_open_fp_valid_file(void) {
    /* Create a temporary file */
    char tmppath[] = "/tmp/pbzx_test_XXXXXX";
    int fd = mkstemp(tmppath);
    ASSERT(fd >= 0);
    write(fd, "hello", 5);
    close(fd);

    struct stream s;
    ASSERT(stream_open(&s, STREAM_FP, tmppath));
    ASSERT_EQ(STREAM_FP, s.type);
    ASSERT(s.fp != NULL);
    stream_close(&s);
    ASSERT_EQ(0, s.type);
    ASSERT_EQ(NULL, s.fp);

    unlink(tmppath);
    PASS();
}

TEST test_stream_open_fp_nonexistent(void) {
    struct stream s;
    ASSERT_FALSE(stream_open(&s, STREAM_FP, "/tmp/pbzx_nonexistent_file_12345"));
    PASS();
}

TEST test_stream_open_invalid_type(void) {
    struct stream s;
    ASSERT_FALSE(stream_open(&s, 99, "dummy"));
    PASS();
}

SUITE(suite_stream_open) {
    RUN_TEST(test_stream_open_fp_valid_file);
    RUN_TEST(test_stream_open_fp_nonexistent);
    RUN_TEST(test_stream_open_invalid_type);
}

/* ========== stream_read() tests ========== */

TEST test_stream_read_null_stream(void) {
    char buf[16];
    ASSERT_EQ(0, stream_read(buf, 16, NULL));
    PASS();
}

TEST test_stream_read_fp_returns_byte_count(void) {
    char tmppath[] = "/tmp/pbzx_test_read_XXXXXX";
    int fd = mkstemp(tmppath);
    ASSERT(fd >= 0);
    write(fd, "ABCDEFGH", 8);
    close(fd);

    struct stream s;
    ASSERT(stream_open(&s, STREAM_FP, tmppath));

    char buf[8] = {0};
    uint32_t ret = stream_read(buf, 8, &s);
    ASSERT_EQ(8, ret);
    ASSERT_MEM_EQ("ABCDEFGH", buf, 8);

    stream_close(&s);
    unlink(tmppath);
    PASS();
}

SUITE(suite_stream_read) {
    RUN_TEST(test_stream_read_null_stream);
    RUN_TEST(test_stream_read_fp_returns_byte_count);
}

/* ========== stream_read_64() tests ========== */

TEST test_stream_read_64_big_endian(void) {
    /* Write 0x0123456789ABCDEF in big-endian to a file */
    char tmppath[] = "/tmp/pbzx_test_r64_XXXXXX";
    int fd = mkstemp(tmppath);
    ASSERT(fd >= 0);
    unsigned char data[8] = {0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF};
    write(fd, data, 8);
    close(fd);

    struct stream s;
    ASSERT(stream_open(&s, STREAM_FP, tmppath));
    uint64_t val = stream_read_64(&s);
    ASSERT_EQ(0x0123456789ABCDEFULL, val);

    stream_close(&s);
    unlink(tmppath);
    PASS();
}

TEST test_stream_read_64_zeros(void) {
    char tmppath[] = "/tmp/pbzx_test_r64z_XXXXXX";
    int fd = mkstemp(tmppath);
    ASSERT(fd >= 0);
    unsigned char data[8] = {0};
    write(fd, data, 8);
    close(fd);

    struct stream s;
    ASSERT(stream_open(&s, STREAM_FP, tmppath));
    uint64_t val = stream_read_64(&s);
    ASSERT_EQ(0ULL, val);

    stream_close(&s);
    unlink(tmppath);
    PASS();
}

SUITE(suite_stream_read_64) {
    RUN_TEST(test_stream_read_64_big_endian);
    RUN_TEST(test_stream_read_64_zeros);
}

/* ========== parse_args() tests ========== */

TEST test_parse_args_no_flags(void) {
    const char* argv[] = {"pbzx", "file.pkg"};
    int argc = 2;
    struct options opts = {0};
    parse_args(&argc, argv, &opts);
    ASSERT_FALSE(opts.stdin);
    ASSERT_FALSE(opts.noxar);
    ASSERT_FALSE(opts.help);
    ASSERT_FALSE(opts.version);
    ASSERT_STR_EQ("file.pkg", opts.filename);
    PASS();
}

TEST test_parse_args_stdin_flag(void) {
    const char* argv[] = {"pbzx", "-", NULL};
    int argc = 2;
    struct options opts = {0};
    parse_args(&argc, argv, &opts);
    ASSERT(opts.stdin);
    ASSERT_EQ(NULL, opts.filename);
    PASS();
}

TEST test_parse_args_noxar_flag(void) {
    const char* argv[] = {"pbzx", "-n", "file.bin", NULL};
    int argc = 3;
    struct options opts = {0};
    parse_args(&argc, argv, &opts);
    ASSERT(opts.noxar);
    ASSERT_STR_EQ("file.bin", opts.filename);
    PASS();
}

TEST test_parse_args_multiple_flags(void) {
    const char* argv[] = {"pbzx", "-n", "-", NULL};
    int argc = 3;
    struct options opts = {0};
    parse_args(&argc, argv, &opts);
    ASSERT(opts.noxar);
    ASSERT(opts.stdin);
    ASSERT_EQ(NULL, opts.filename);
    PASS();
}

SUITE(suite_parse_args) {
    RUN_TEST(test_parse_args_no_flags);
    RUN_TEST(test_parse_args_stdin_flag);
    RUN_TEST(test_parse_args_noxar_flag);
    RUN_TEST(test_parse_args_multiple_flags);
}

/* ========== Main ========== */

GREATEST_MAIN_DEFS();

int main(int argc, char **argv) {
    GREATEST_MAIN_BEGIN();
    RUN_SUITE(suite_min);
    RUN_SUITE(suite_stream_init);
    RUN_SUITE(suite_stream_open);
    RUN_SUITE(suite_stream_read);
    RUN_SUITE(suite_stream_read_64);
    RUN_SUITE(suite_parse_args);
    GREATEST_MAIN_END();
}
