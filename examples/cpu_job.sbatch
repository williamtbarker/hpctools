#!/usr/bin/env bash
#SBATCH --job-name=example-cpu
#SBATCH --partition=cpu-q
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=00:30:00
#SBATCH --output=example-cpu-%j.out
#SBATCH --error=example-cpu-%j.err

set -Eeuo pipefail
umask 0077

printf 'job=%s host=%s cpus=%s\n' \
  "${SLURM_JOB_ID:-local}" \
  "$(hostname)" \
  "${SLURM_CPUS_PER_TASK:-1}"
