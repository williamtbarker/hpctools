#!/usr/bin/env bash
set -u

project_root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/hpctools-tests.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

original_path=$PATH
export PATH="$project_root/bin:$project_root/tests/fakes:$PATH"
export HPCTOOLS_USER="tester"

passed=0
failed=0
tests_run=0

assert_contains() {
  haystack=$1
  needle=$2
  case "$haystack" in
    *"$needle"*) return 0 ;;
    *) printf 'expected output to contain: %s\nactual: %s\n' "$needle" "$haystack" >&2; return 1 ;;
  esac
}

test_render_and_strict_lint() {
  test_dir="$temporary_root/render"
  mkdir -p "$test_dir"
  output="$test_dir/job.sbatch"
  slurm-render \
    --output "$output" \
    --job-name qc \
    --partition cpu-q \
    --cpus 4 \
    --mem 8G \
    --time 01:30:00 \
    --array 1-8%2 \
    -- python analysis.py --input "reads one.fastq" >/dev/null || return 1
  grep -Fx '#SBATCH --array=1-8%2' "$output" >/dev/null || return 1
  grep -F "exec python analysis.py --input reads\\ one.fastq" "$output" >/dev/null || return 1
  slurm-lint --strict "$output" >/dev/null || return 1
}

test_render_refuses_overwrite() {
  test_dir="$temporary_root/overwrite"
  mkdir -p "$test_dir"
  output="$test_dir/job.sbatch"
  : >"$output"
  if slurm-render --output "$output" --job-name x --time 00:01:00 --mem 1G -- true >/dev/null 2>&1; then
    return 1
  fi
}

test_render_rejects_invalid_resources() {
  test_dir="$temporary_root/invalid-render"
  mkdir -p "$test_dir"
  if slurm-render --output "$test_dir/time.sbatch" --job-name x --time 00:99:00 --mem 1G -- true >/dev/null 2>&1; then
    return 1
  fi
  if slurm-render --output "$test_dir/mem.sbatch" --job-name x --time 00:01:00 --mem 0G -- true >/dev/null 2>&1; then
    return 1
  fi
  if slurm-render --output "$test_dir/array.sbatch" --job-name x --time 00:01:00 --mem 1G --array '1-3;id' -- true >/dev/null 2>&1; then
    return 1
  fi
  if slurm-render --output "$test_dir/injected.sbatch" --job-name x --time 00:01:00 --mem 1G --stdout $'safe.out\n#SBATCH --account=other' -- true >/dev/null 2>&1; then
    return 1
  fi
}

test_lint_finds_contract_failures() {
  output="$temporary_root/lint.out"
  if slurm-lint "$project_root/tests/fixtures/bad.sbatch" >"$output" 2>&1; then
    return 1
  fi
  contents=$(cat "$output")
  assert_contains "$contents" "D001" || return 1
  assert_contains "$contents" "D102" || return 1
  assert_contains "$contents" "R001" || return 1
}

make_two_jobs() {
  job_dir=$1
  mkdir -p "$job_dir"
  slurm-render --output "$job_dir/one.sbatch" --job-name one --time 00:01:00 --mem 1G -- true >/dev/null
  slurm-render --output "$job_dir/two.sbatch" --job-name two --time 00:01:00 --mem 1G -- true >/dev/null
}

test_chain_dry_run_and_submission() {
  test_dir="$temporary_root/chain"
  make_two_jobs "$test_dir" || return 1
  export HPC_FAKE_SBATCH_LOG="$test_dir/sbatch.log"
  export HPC_FAKE_SBATCH_COUNTER="$test_dir/counter"
  : >"$HPC_FAKE_SBATCH_LOG"
  printf '1000\n' >"$HPC_FAKE_SBATCH_COUNTER"
  plan=$(slurm-chain "$test_dir/one.sbatch" "$test_dir/two.sbatch") || return 1
  assert_contains "$plan" "DRY_RUN" || return 1
  [ ! -s "$HPC_FAKE_SBATCH_LOG" ] || return 1
  result=$(slurm-chain --submit "$test_dir/one.sbatch" "$test_dir/two.sbatch") || return 1
  assert_contains "$result" $'SUBMITTED\t1\t1001' || return 1
  assert_contains "$(cat "$HPC_FAKE_SBATCH_LOG")" "--dependency=afterok:1001" || return 1
}

test_chain_lints_everything_before_submission() {
  test_dir="$temporary_root/chain-lint"
  make_two_jobs "$test_dir" || return 1
  export HPC_FAKE_SBATCH_LOG="$test_dir/sbatch.log"
  export HPC_FAKE_SBATCH_COUNTER="$test_dir/counter"
  : >"$HPC_FAKE_SBATCH_LOG"
  printf '2000\n' >"$HPC_FAKE_SBATCH_COUNTER"
  if slurm-chain --submit "$test_dir/one.sbatch" "$project_root/tests/fixtures/bad.sbatch" >/dev/null 2>&1; then
    return 1
  fi
  [ ! -s "$HPC_FAKE_SBATCH_LOG" ] || return 1
}

test_wait_reports_transitions_and_completion() {
  test_dir="$temporary_root/wait"
  mkdir -p "$test_dir"
  export HPC_FAKE_STATE_FILE="$test_dir/states"
  export HPC_FAKE_SACCT_STATE="COMPLETED"
  unset HPC_FAKE_STATE
  printf 'PENDING\nRUNNING\n' >"$HPC_FAKE_STATE_FILE"
  output=$(slurm-wait --job 42 --interval 0 --unknown-limit 2) || return 1
  assert_contains "$output" $'STATE\tPENDING' || return 1
  assert_contains "$output" $'STATE\tRUNNING' || return 1
  assert_contains "$output" $'STATE\tCOMPLETED' || return 1
}

test_wait_propagates_failure() {
  test_dir="$temporary_root/wait-failure"
  mkdir -p "$test_dir"
  export HPC_FAKE_STATE_FILE="$test_dir/states"
  export HPC_FAKE_SACCT_STATE="FAILED"
  : >"$HPC_FAKE_STATE_FILE"
  if slurm-wait --job 43 --interval 0 >/dev/null 2>&1; then
    return 1
  fi
}

test_wait_limits_unknown_accounting() {
  test_dir="$temporary_root/wait-unknown"
  mkdir -p "$test_dir"
  export HPC_FAKE_STATE_FILE="$test_dir/states"
  export HPC_FAKE_SACCT_STATE=""
  : >"$HPC_FAKE_STATE_FILE"
  if slurm-wait --job 44 --interval 0 --unknown-limit 2 >/dev/null 2>&1; then
    return 1
  fi
}

test_cancel_is_dry_by_default_and_checks_owner() {
  test_dir="$temporary_root/cancel"
  mkdir -p "$test_dir"
  export HPC_FAKE_SCANCEL_LOG="$test_dir/scancel.log"
  export HPC_FAKE_OWNER="tester"
  export HPC_FAKE_STATE="RUNNING"
  export HPC_FAKE_JOB_PRESENT="1"
  unset HPC_FAKE_STATE_FILE
  : >"$HPC_FAKE_SCANCEL_LOG"
  output=$(slurm-cancel 77) || return 1
  assert_contains "$output" "WOULD_CANCEL" || return 1
  [ ! -s "$HPC_FAKE_SCANCEL_LOG" ] || return 1
  slurm-cancel --confirm 77 >/dev/null || return 1
  [ "$(cat "$HPC_FAKE_SCANCEL_LOG")" = "77" ] || return 1
  export HPC_FAKE_OWNER="someone-else"
  if slurm-cancel --confirm 78 >/dev/null 2>&1; then
    return 1
  fi
  [ "$(wc -l <"$HPC_FAKE_SCANCEL_LOG" | tr -d ' ')" = "1" ] || return 1
}

test_cancel_rejects_non_job_identifiers() {
  if slurm-cancel --confirm '77;whoami' >/dev/null 2>&1; then
    return 1
  fi
}

test_doctor_reports_ready_environment() {
  export HPC_FAKE_ACTIVE_JOBS="2"
  output=$(hpc-doctor --path "$temporary_root" --require-slurm) || return 1
  assert_contains "$output" $'ACTIVE_JOBS\t2' || return 1
  assert_contains "$output" $'STATUS\tready' || return 1
}

test_install_layout_runs() {
  stage="$temporary_root/stage"
  make -s -C "$project_root" install DESTDIR="$stage" PREFIX=/usr/local || return 1
  [ -x "$stage/usr/local/bin/slurm-lint" ] || return 1
  [ -r "$stage/usr/local/lib/hpctools/common.sh" ] || return 1
  PATH="$stage/usr/local/bin:$original_path" "$stage/usr/local/bin/slurm-lint" --version \
    | grep -F '0.1.0' >/dev/null || return 1
}

test_all_commands_have_help() {
  for command_name in hpc-doctor slurm-cancel slurm-chain slurm-lint slurm-render slurm-wait; do
    "$project_root/bin/$command_name" --help >/dev/null || return 1
  done
}

run_test() {
  test_name=$1
  shift
  tests_run=$((tests_run + 1))
  if "$@"; then
    passed=$((passed + 1))
    printf 'ok %s - %s\n' "$tests_run" "$test_name"
  else
    failed=$((failed + 1))
    printf 'not ok %s - %s\n' "$tests_run" "$test_name"
  fi
}

printf 'TAP version 13\n'
run_test "render and strict lint" test_render_and_strict_lint
run_test "render refuses overwrite" test_render_refuses_overwrite
run_test "render validates resources" test_render_rejects_invalid_resources
run_test "lint detects failures" test_lint_finds_contract_failures
run_test "dependency chain" test_chain_dry_run_and_submission
run_test "chain preflights all scripts" test_chain_lints_everything_before_submission
run_test "wait completes" test_wait_reports_transitions_and_completion
run_test "wait fails" test_wait_propagates_failure
run_test "wait limits unknown state" test_wait_limits_unknown_accounting
run_test "safe cancellation" test_cancel_is_dry_by_default_and_checks_owner
run_test "cancel validates job IDs" test_cancel_rejects_non_job_identifiers
run_test "environment doctor" test_doctor_reports_ready_environment
run_test "install layout" test_install_layout_runs
run_test "command help" test_all_commands_have_help
printf '1..%s\n' "$tests_run"

[ "$failed" -eq 0 ]
