# hpctools

[![CI](https://github.com/williamtbarker/hpctools/actions/workflows/ci.yml/badge.svg)](https://github.com/williamtbarker/hpctools/actions/workflows/ci.yml)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-clean-brightgreen.svg)](https://www.shellcheck.net/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

`hpctools` is a Bash-first command-line toolkit for routine Slurm work. It creates and checks batch
scripts, plans dependency chains, waits for terminal job states, performs ownership-checked
cancellation, and captures a read-only cluster diagnostic snapshot.

The tools favor explicit contracts over site-specific automation. They do not assume a partition,
module system, container runtime, cloud provider, filesystem layout, or scientific workflow.

## Commands

| Command | Purpose | Controller required? |
|---|---|---:|
| `hpc-doctor` | Report command availability, filesystem facts, partitions, and active-job count | Optional |
| `slurm-render` | Generate a deterministic batch script without overwriting by default | No |
| `slurm-lint` | Check batch-script structure, required resources, and risky operations | No |
| `slurm-chain` | Lint and plan or submit a linear `afterok`/`afterany` chain | Submit only |
| `slurm-wait` | Poll `squeue` and `sacct` until a job reaches a terminal state | Yes |
| `slurm-cancel` | Preview or cancel exact job IDs after verifying ownership | Yes |

## Install

No runtime package manager is required. Bash 3.2 or newer is supported.

```bash
make test
make install PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
```

For development checks, install [ShellCheck](https://www.shellcheck.net/):

```bash
# macOS
brew install shellcheck

./scripts/verify.sh
```

You can also run every command directly from `bin/` without installing it.

## Quick tour

Inspect a login-node environment without changing it:

```bash
hpc-doctor --path "$PWD"
```

Create a batch script while preserving each command argument safely:

```bash
slurm-render \
  --output qc.sbatch \
  --job-name qc \
  --partition cpu-q \
  --cpus 4 \
  --mem 8G \
  --time 02:00:00 \
  -- python analysis.py --input "reads one.fastq.gz"
```

Audit it locally:

```bash
slurm-lint --strict qc.sbatch
```

Plan a dependency chain. This does **not** submit anything:

```bash
slurm-chain prepare.sbatch analyze.sbatch report.sbatch
```

Submit only after reviewing the plan:

```bash
slurm-chain --submit prepare.sbatch analyze.sbatch report.sbatch
```

Wait for a job and propagate its outcome to the shell:

```bash
slurm-wait --job 12345 --interval 10 --timeout 7200
```

Preview a cancellation, then repeat with explicit confirmation:

```bash
slurm-cancel 12345
slurm-cancel --confirm 12345
```

## Safety model

- `slurm-chain` is a planner unless `--submit` is present.
- `slurm-chain` lints every file before submitting the first job.
- `slurm-cancel` accepts exact job IDs only; there is no cancel-by-user or cancel-by-name mode.
- `slurm-cancel` verifies that an active job belongs to the current user before calling `scancel`.
- Generated scripts are written atomically with mode `0755`, `set -Eeuo pipefail`, and `umask 0077`.
- Existing render targets are preserved unless `--force` is explicit.
- The linter calls attention to recursive forced deletion, bulk cancellation, `find -delete`, and
  `aws s3 sync --delete`; it does not execute inspected scripts.
- No tool reads credentials, submits through SSH, or modifies scheduler configuration.

These controls reduce common operator mistakes; they do not replace local cluster policy or review
by an administrator. Always inspect a submission plan and the generated batch script.

## `slurm-lint` contract

The linter requires a Bash shebang and explicit directives for job name, time, CPUs, memory, and
standard output. Missing error output, strict mode, or a restrictive `umask` produces a warning.
Directives placed after executable content are errors because Slurm ignores late directives.

Exit status is `0` when there are no errors. `--strict` also treats warnings as failure. The check is
intentionally narrow and explainable; ShellCheck remains the deeper shell-language analyzer.

## `slurm-wait` exit statuses

| Status | Meaning |
|---:|---|
| `0` | Slurm reported `COMPLETED` |
| `1` | Slurm reported another terminal state or the job remained unknown |
| `2` | Command-line usage error |
| `124` | The local `--timeout` elapsed |
| `127` | A required Slurm command was missing |

## Testing without a cluster

The test suite supplies deterministic fake implementations of `sbatch`, `squeue`, `sacct`,
`scancel`, and `sinfo`. This exercises argument construction, dependency IDs, state transitions,
ownership checks, and installation on ordinary Linux or macOS systems without contacting Slurm.
CI repeats Bash syntax checks, ShellCheck, mocked workflows, example linting, and a staged install on
both Ubuntu and macOS.

Mocked tests establish local program behavior; they are not evidence that a particular cluster's
partitions, accounting configuration, or policy will accept a job.

## Project provenance

The recurring operational patterns were recovered from several years of HPC and Slurm work in a
private technical-chat archive. The public implementation was reconstructed as a generic toolkit:
employer-specific hosts, account identifiers, storage locations, credentials, scientific workflow
details, and destructive cleanup recipes were deliberately excluded.

## License

MIT. See [LICENSE](LICENSE).
