SLURM_VERSION = 25.11.0
IMAGE = hpcdrifter/slurm.rpms
OPENMPI_VERSION = v5.0
OPENMPI_RPM = openmpi-5.0.8.tar.gz
PLT = x86_64

DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: all build clean test

all: build

build: rpms

rpms:
	@docker buildx build --platform linux/$(PLT) -t $(IMAGE):$(SLURM_VERSION) .
	@docker run --rm \
		-e SLURM_VERSION=$(SLURM_VERSION) \
		-e OPENMPI_VERSION=$(OPENMPI_VERSION) \
		-e OPENMPI_RPM=$(OPENMPI_RPM) \
		-e ARCH=$(PLT) \
		-v "$(DIR)/rpms:/packages" $(IMAGE):$(SLURM_VERSION)

clean:
	@[ -z "$$(docker images -q $(IMAGE):$(SLURM_VERSION))" ] || docker rmi $(IMAGE):$(SLURM_VERSION)
	@rm -rf rpms