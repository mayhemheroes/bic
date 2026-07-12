#!/usr/bin/env bash
#
# mayhem/build.sh — build bic's fuzz harness + the upstream test suite.
#
# Target: the language-description parser (src/lang_lexer.lpp + src/lang.cpp) that the
# gen* code generators (genaccess, gentree, ...) use to read `c.lang`. The upstream Mayhem
# target `genaccess @@` drives this same parser but then writes tree-access.h to the CWD,
# which aborts under Mayhem's read-only image mount; mayhem/fuzz_lang.cpp is an in-process
# libFuzzer harness calling lang_read() over the identical parse path without the codegen
# output (the parser's exit(1) error path is contained via -Wl,--wrap=exit).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# bic's configure.ac calls LT_SYS_SYMBOL_USCORE, dropped from libtool >= 2.5; supply a shim.
export ACLOCAL_PATH="$SRC/mayhem/m4${ACLOCAL_PATH:+:$ACLOCAL_PATH}"

# bic's m4-generated lexers use srcdir-relative m4 includes, which breaks VPATH builds —
# build IN-TREE in two independent source copies instead (sanitized fuzz build + normal test build).
copytree() {
  rm -rf "$1"; mkdir -p "$1"
  tar -C "$SRC" --exclude=./build-fuzz --exclude=./build-tests --exclude=./.git -cf - . \
    | tar -C "$1" -xf -
}

# 1) Sanitized + SanitizerCoverage build (instruments the fuzzed parser code, DWARF<4).
#    -fsanitize=fuzzer-no-link adds the coverage instrumentation libFuzzer/Mayhem need for
#    edge feedback (a raw uninstrumented file-input build reports 0 edges in Mayhem).
copytree "$SRC/build-fuzz"
( cd "$SRC/build-fuzz"
  autoreconf -i
  ./configure --enable-debug CC="$CC" CXX="$CXX" \
      CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
      CXXFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
  make -j"$MAYHEM_JOBS" )

# 2) Fuzz harness (in-process libFuzzer): link the instrumented lang parser objects.
#    -Wl,--wrap=exit routes the parser's exit(1) error path back to the harness (siglongjmp)
#    so invalid inputs don't kill the persistent fuzzing process.
"$CXX" $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$SRC/mayhem/fuzz_lang.cpp" \
    "$SRC/build-fuzz/src/lang.o" \
    "$SRC/build-fuzz/src/lang_lexer.o" \
    -I"$SRC/src" -I"$SRC/build-fuzz/src" \
    -Wl,--wrap=exit \
    -o /mayhem/genaccess_fuzz

# 2b) Standalone (non-fuzzer) run-once reproducer for crash triage — same harness, LLVM's
#     standalone driver instead of libFuzzer (compile the C driver separately: clang++ would
#     mangle its LLVMFuzzerTestOneInput reference).
"$CC" $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
"$CXX" $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS \
    "$SRC/mayhem/fuzz_lang.cpp" \
    /tmp/standalone_main.o \
    "$SRC/build-fuzz/src/lang.o" \
    "$SRC/build-fuzz/src/lang_lexer.o" \
    -I"$SRC/src" -I"$SRC/build-fuzz/src" \
    -Wl,--wrap=exit \
    -o /mayhem/genaccess_fuzz-standalone

# 3) Test-suite build with the project's NORMAL flags (a clean, independent tree) so mayhem/test.sh
#    only has to RUN it. `make check TESTS=` builds the check_PROGRAMS without running any test.
copytree "$SRC/build-tests"
( cd "$SRC/build-tests"
  autoreconf -i
  ./configure --enable-debug CC="$CC" CXX="$CXX" \
      CFLAGS="-O1 -g $COVERAGE_FLAGS" CXXFLAGS="-O1 -g $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS"
  make -j"$MAYHEM_JOBS"
  make -j"$MAYHEM_JOBS" check TESTS= )

echo "build.sh: done — /mayhem/genaccess_fuzz (+ -standalone) + test tree in $SRC/build-tests"
