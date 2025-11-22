SLURM_VERSION = 25.11.0
IMAGE = hpcdrifter/slurm.controller
PLT= x86_64

.PHONY: all build clean test

all: build

build:
	docker buildx build --platform linux/$(PLT) -t $(IMAGE):$(SLURM_VERSION) .

clean:
	@[ -z "$$(docker images -q $(IMAGE):$(SLURM_VERSION))" ] || docker rmi $(IMAGE):$(SLURM_VERSION)
