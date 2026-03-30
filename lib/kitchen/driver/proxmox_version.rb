# frozen_string_literal: true

module Kitchen
  module Driver
    PROXMOX_VERSION = begin
      # When loaded from a git checkout, derive the version from git tags.
      # When installed as a gem, git isn't available so fall back to the
      # version baked into the gemspec at build time.
      dir = File.expand_path('../../..', __dir__)
      if File.directory?(File.join(dir, '.git'))
        tag = `git -C #{dir} describe --tags --match 'v*' 2>/dev/null`.strip
        tag.empty? ? '0.0.0' : tag.sub(/^v/, '').sub(/-(\d+)-g/, '.\1.dev.')
      else
        Gem.loaded_specs['kitchen-proxmox']&.version&.to_s || '0.0.0'
      end
    end
  end
end
