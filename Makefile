subdir = packages base controller worker database login

.PHONY: all build clean lint test $(subdir) docker-clean docker-stop docker-remove-volumes clean-dirs

all: build

build: $(subdir)

clean: docker-clean clean-dirs $(subdir)

docker-clean: docker-stop docker-remove-volumes

docker-stop:
	@echo "Stopping Docker Compose services..."
	docker-compose down || true

docker-remove-volumes:
	@echo "Removing Docker volumes..."
	docker-compose down -v || true

clean-dirs:
	@echo "Removing ./secret directory..."
	rm -rf ./secret || true
	@echo "Removing ./home directory..."
	rm -rf ./home || true
	@echo "Directory cleanup completed"

test:
	$(MAKE) -C $@

lint:
	shellcheck **/*.sh

controller worker database: base

base: packages

$(subdir):
	$(MAKE) -C $@ $(MAKECMDGOALS)