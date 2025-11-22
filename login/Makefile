
SLURM_VERSION = 25.11.0
IMAGE = hpcdrifter/slurm.login
PLT= x86_64
DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: all build clean run shell

all: build

# Build from repository root so `packages/rocky/rpms` is available in the build context
build:
	cp -r "$(DIR)/../packages/rocky/rpms" .
	docker buildx build --platform linux/$(PLT) -t $(IMAGE):$(SLURM_VERSION) .

clean:
	@[ -z "$(shell docker images -q $(IMAGE):$(SLURM_VERSION))" ] || docker rmi $(IMAGE):$(SLURM_VERSION)
	@rm -rf rpms

run:
	# Run interactive shell; mount a `.secret` volume if present for SSH secrets
	# Optionally mount the local rpms directory at /rpms for runtime access
	docker run --rm -it \
		-v $$(pwd)/.secret:/.secret:ro \
		-v $$(pwd)/packages/rocky/rpms:/rpms:ro \
		$(IMAGE):$(SLURM_VERSION)

shell:
	# Start a container and drop to an interactive shell
	docker run --rm -it $(IMAGE):$(SLURM_VERSION) /bin/bash
