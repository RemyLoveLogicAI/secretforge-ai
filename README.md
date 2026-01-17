# secretforge-ai

Secret scanning CI setup using a reusable composite GitHub Action.

## CI secret scanning
- Workflow: `.github/workflows/secretforge.yml` runs on push/PR to `main`.
- Action: `.github/actions/secret-scan` installs `secretforge`, `trufflehog==2.2.1`, and `GitPython==3.0.6`, scans, and optionally fails on findings.
- Artifacts: Uploads `secret-scan.json` as `secret-scan-report` and writes a short summary to the job log/step summary.

### Composite action inputs
- `path` (default `.`): Repo path to scan.
- `branch` (default `HEAD`): Ref to scan (git mode only).
- `max_depth` (default `0` = full history): Commit depth (git mode only).
- `mode` (default `git`): `git` scans history; `filesystem` scans the working tree and skips history.
- `include_paths_file` / `exclude_paths_file`: Optional regex filters (one per line) passed to trufflehog `-i/-x` (git mode). Default excludes are applied: `.git/`, `.venv/`, `node_modules/`, `vendor/`, `dist/`, `build/`.
- `output` (default `secret-scan.json`): Report file.
- `fail_on_find` (default `true`): Fail job if report is non-empty.

### Local usage
```bash
npm install -g secretforge
python3 -m pip install "GitPython==3.0.6" "trufflehog==2.2.1"
trufflehog --json --regex --entropy True --max_depth 0 --branch HEAD --repo_path . . > secret-scan.json
```
Add `-i include.txt` or `-x exclude.txt` to narrow or skip paths; files contain regexes, one per line.

### Notes
- Ensure the repo has full history for git mode; CI checkout uses `fetch-depth: 0`.
- Repos with no commits will skip git-mode scan; switch to `mode: filesystem` if you need a working-tree scan.
- Default excludes skip typical dependency/build dirs; provide your own `exclude_paths_file` to override/extend.
- The action only scans and reports; it does not rotate or remove secrets.

## License
MIT (see LICENSE).

## Contributing
See CONTRIBUTING. Add tests for changes when possible.
