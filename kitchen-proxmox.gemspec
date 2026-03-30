# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kitchen/driver/proxmox_version'

Gem::Specification.new do |spec|
  spec.name          = 'kitchen-proxmox'
  spec.version       = Kitchen::Driver::PROXMOX_VERSION
  spec.authors       = ['Richard Nixon']
  spec.email         = ['richard.nixon@btinternet.com']
  spec.summary       = 'Test Kitchen driver for Proxmox VE'
  spec.description   = 'A Test Kitchen driver for Proxmox VE. ' \
                       'Manages VM lifecycle (create, destroy) via the Proxmox REST API. ' \
                       'Supports cloning from templates.'
  spec.homepage      = 'https://github.com/trickyearlobe-chef/kitchen-proxmox'
  spec.license       = 'Apache-2.0'

  spec.files         = Dir['lib/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1'

  # This gem requires test-kitchen and its dependencies at runtime, but we
  # intentionally declare NO gem dependencies here. Chef Workstation already
  # provides test-kitchen and a curated set of gems. Declaring dependencies
  # causes bundler/gem to resolve and install versions that conflict with
  # Chef Workstation's signed Ruby and native extensions (e.g. bigdecimal
  # code signing failures on macOS). Install this gem into Chef Workstation
  # with: chef exec gem install kitchen-proxmox
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['source_code_uri']        = 'https://github.com/trickyearlobe-chef/kitchen-proxmox'
  spec.metadata['bug_tracker_uri']        = 'https://github.com/trickyearlobe-chef/kitchen-proxmox/issues'
  spec.metadata['changelog_uri']          = 'https://github.com/trickyearlobe-chef/kitchen-proxmox/blob/main/CHANGELOG.md'
end
