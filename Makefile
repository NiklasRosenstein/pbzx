CC       ?= clang
CFLAGS   ?= -Wall -Wextra -O2
PREFIX   ?= /usr/local

# Detect Homebrew prefix (macOS)
HOMEBREW := $(shell brew --prefix 2>/dev/null)
ifdef HOMEBREW
INCLUDES := -I$(HOMEBREW)/include
LDFLAGS  := -L$(HOMEBREW)/lib
endif

LIBS := -llzma -lxar

.PHONY: all clean test fixtures

all: pbzx

pbzx: pbzx.c
	$(CC) $(CFLAGS) $(INCLUDES) $< -o $@ $(LDFLAGS) $(LIBS)

# Download greatest.h test framework
tests/greatest.h:
	curl -sL -o $@ https://raw.githubusercontent.com/silentbicycle/greatest/v1.5.0/greatest.h

# Build C unit test binary
test_pbzx: tests/test_pbzx.c pbzx.c tests/greatest.h
	$(CC) $(CFLAGS) $(INCLUDES) -DTESTING -I tests $< -o $@ $(LDFLAGS) $(LIBS)

# Generate test fixtures
fixtures:
	python3 tests/gen_fixtures.py

# Run all tests
test: pbzx test_pbzx fixtures
	@echo "=== Running C unit tests ==="
	./test_pbzx
	@echo ""
	@echo "=== Running integration tests ==="
	bash tests/run_tests.sh

clean:
	rm -f pbzx test_pbzx
	rm -rf tests/fixtures
