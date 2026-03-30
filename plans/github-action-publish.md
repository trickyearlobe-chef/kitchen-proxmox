# Plan: GitHub Action to Publish Gem

## Goal
Add GitHub Actions workflows for CI and gem publishing to RubyGems.

## Reference
kitchen-vagrant uses `release-please` + `publish-gem-to-rubygems`. We follow the same pattern but simplified (no GitHub Packages, no release-please bot token).

## Steps
1. Create `.github/workflows/ci.yml` — runs rspec and rubocop on PRs and pushes.
2. Create `.github/workflows/publish.yml` — triggered on GitHub Release; builds and pushes to RubyGems.
3. Update README with badge and release instructions.

## Acceptance Criteria
- CI runs on push to main and on PRs.
- Publish runs only when a GitHub Release is created.
- RubyGems publish uses `RUBYGEMS_API_KEY` secret.
- Workflows use pinned action versions.
