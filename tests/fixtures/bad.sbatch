#!/usr/bin/env bash
#SBATCH --job-name=bad
#SBATCH --cpus-per-task=2
#SBATCH --output=bad-%j.out

echo "started"
#SBATCH --mem=8G
rm -rf "$WORK_DIRECTORY"
