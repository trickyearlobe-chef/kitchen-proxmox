# Plan: Project Scaffolding

## Goal

Set up the kitchen-proxmox gem project with specs-first TDD approach, following kitchen-vagrant conventions.

## Steps

1. Write gem scaffolding (Gemfile, gemspec, Rakefile, .rspec, .rubocop.yml, .gitignore, LICENSE)
2. Write spec_helper.rb
3. Write specs for the API client (`spec/kitchen/driver/proxmox/api_client_spec.rb`)
4. Write specs for the driver (`spec/kitchen/driver/proxmox_spec.rb`)
5. Implement the version file (`lib/kitchen/driver/proxmox_version.rb`)
6. Implement the API client (`lib/kitchen/driver/proxmox/api_client.rb`)
7. Implement the driver (`lib/kitchen/driver/proxmox.rb`)
8. Run specs, fix until green
9. Run chefstyle, fix until clean
10. Write README.md and CHANGELOG.md
11. git init and initial commit

## Acceptance Criteria

- `bundle exec rake spec` passes
- `bundle exec rake style` passes
- File layout matches kitchen-vagrant conventions per CLAUDE.md
