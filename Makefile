PREFIX ?= /usr/local
DESTDIR ?=
BINDIR = $(DESTDIR)$(PREFIX)/bin
LIBDIR = $(DESTDIR)$(PREFIX)/lib/hpctools

.PHONY: all install test lint verify

all: test

install:
	install -d "$(BINDIR)" "$(LIBDIR)"
	install -m 0755 bin/hpc-doctor bin/slurm-cancel bin/slurm-chain \
		bin/slurm-lint bin/slurm-render bin/slurm-wait "$(BINDIR)"
	install -m 0644 lib/hpctools/common.sh "$(LIBDIR)/common.sh"

test:
	./tests/run_tests.sh

lint:
	shellcheck -x bin/* examples/*.sbatch lib/hpctools/*.sh scripts/*.sh tests/*.sh tests/fakes/*

verify:
	./scripts/verify.sh
