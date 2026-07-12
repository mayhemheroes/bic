/*
 * fuzz_lang.cpp — in-process libFuzzer harness driving bic's language-description
 * parser (src/lang_lexer.lpp + src/lang.cpp), the same lexer/parser genaccess and
 * the other gen* code generators use to read `c.lang`.
 *
 * The upstream Mayhem target was `genaccess @@`, whose main() parses the input with
 * lang_read() and then WRITES tree-access.h into the CWD (aborts under Mayhem's
 * read-only image mount). A raw file-input rewrite carries no SanitizerCoverage
 * instrumentation, so Mayhem sees 0 edges. This harness drives the identical parse
 * path (lang_read) in-process instead.
 *
 * The parser reports syntax errors by calling exit(1) (an allocate-and-exit batch
 * tool). To keep the process alive, the link wraps exit (-Wl,--wrap=exit): during a
 * parse, __wrap_exit longjmps back here; outside a parse (e.g. libFuzzer's own
 * shutdown) it forwards to the real exit. longjmp skips C++ destructors on the
 * error path, so leak detection is disabled — standard for exit-on-error batch
 * tools whose error path never frees.
 */
#include <csetjmp>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include "lang.h"

extern FILE *yyin;
extern void yyrestart(FILE *input_file);

extern "C" void __real_exit(int status) __attribute__((noreturn));

static sigjmp_buf parse_bail;
static volatile int in_parse;

extern "C" void __wrap_exit(int status)
{
    if (in_parse)
        siglongjmp(parse_bail, status ? status : -1);
    __real_exit(status);
}

extern "C" const char *__asan_default_options(void)
{
    return "detect_leaks=0";
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    FILE *f = fmemopen(const_cast<uint8_t *>(data), size, "r");
    if (!f)
        return 0;

    struct lang lang;

    yyrestart(f);
    in_parse = 1;
    if (sigsetjmp(parse_bail, 0) == 0)
        lang_read(f, lang);
    in_parse = 0;

    fclose(f);
    return 0;
}
