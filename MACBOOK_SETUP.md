# macOS verification and publication

From the extracted candidate:

```bash
cd ~/Documents/GPT_Hist_Review/hpctools
brew install shellcheck
./scripts/verify.sh
```

The tests use fake Slurm commands and do not submit, wait for, or cancel real jobs. Actual scheduler
commands should be exercised later on a Slurm login node under that site's policy.

Optional user-local installation:

```bash
make install PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
hpc-doctor --path "$PWD"
```

After verification, initialize and publish the repository:

```bash
git init
git add .
git commit -m "Initial release: safer Slurm command-line workflows"
git branch -M main
gh repo create hpctools --public --source=. --remote=origin --push
```
