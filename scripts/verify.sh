#!/usr/bin/env bash
set -euo pipefail

project_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_root"

for script in bin/* examples/*.sbatch lib/hpctools/*.sh scripts/*.sh tests/*.sh tests/fakes/*; do
  bash -n "$script"
done

./tests/run_tests.sh
./bin/slurm-lint --strict examples/*.sbatch

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x bin/* examples/*.sbatch lib/hpctools/*.sh scripts/*.sh tests/*.sh tests/fakes/*
else
  printf 'shellcheck not installed; skipping static shell analysis\n'
fi

stage_directory=$(mktemp -d "${TMPDIR:-/tmp}/hpctools-stage.XXXXXX")
trap 'rm -rf "$stage_directory"' EXIT HUP INT TERM
make -s install DESTDIR="$stage_directory" PREFIX=/usr/local
test -x "$stage_directory/usr/local/bin/hpc-doctor"
test -r "$stage_directory/usr/local/lib/hpctools/common.sh"

printf 'All checks passed, including mocked Slurm workflows and staged installation.\n'
