.PHONY: all spec style clean install

all: spec style

install:
	chef exec gem build kitchen-proxmox.gemspec
	chef exec gem install kitchen-proxmox-*.gem
	rm -f kitchen-proxmox-*.gem

spec:
	chef exec rspec

style:
	chef exec rubocop

clean:
	rm -rf pkg/ tmp/ coverage/ kitchen-proxmox-*.gem
