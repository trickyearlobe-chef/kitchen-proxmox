CURRENT_VERSION := $(shell git describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(CURRENT_VERSION),)
  CURRENT_VERSION := 0.0.0
endif
MAJOR := $(word 1,$(subst ., ,$(CURRENT_VERSION)))
MINOR := $(word 2,$(subst ., ,$(CURRENT_VERSION)))
PATCH := $(word 3,$(subst ., ,$(CURRENT_VERSION)))

.PHONY: all spec style clean install bump-patch bump-minor bump-major release version

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

version:
	@echo $(CURRENT_VERSION)

bump-patch:
	$(eval NEW_VERSION := $(MAJOR).$(MINOR).$(shell echo $$(($(PATCH)+1))))
	git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Tagged v$(NEW_VERSION)"

bump-minor:
	$(eval NEW_VERSION := $(MAJOR).$(shell echo $$(($(MINOR)+1))).0)
	git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Tagged v$(NEW_VERSION)"

bump-major:
	$(eval NEW_VERSION := $(shell echo $$(($(MAJOR)+1))).0.0)
	git tag -a "v$(NEW_VERSION)" -m "Release v$(NEW_VERSION)"
	@echo "Tagged v$(NEW_VERSION)"

release:
	@if [ -z "$(CURRENT_VERSION)" ] || [ "$(CURRENT_VERSION)" = "0.0.0" ]; then \
		echo "Error: no version tag found. Run make bump-patch/minor/major first."; \
		exit 1; \
	fi
	git push origin main --tags
	@echo "Pushed v$(CURRENT_VERSION)"
