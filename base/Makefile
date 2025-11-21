SLURM_VERSION = 25.11.0
IMAGE = hpcdrifter/slurm.base
PLT= x86_64

DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: all build clean test

all: build

build:
	cp -r "$(DIR)/../packages/rocky-93/rpms" .
	docker buildx build --platform linux/$(PLT) -t $(IMAGE):$(SLURM_VERSION) .

clean:
	@[ -z $(docker images -q $(IMAGE):$(SLURM_VERSION)) ] || docker rmi $(IMAGE):$(SLURM_VERSION)
	rm -rf rpms