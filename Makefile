IMAGE   := ghcr.io/sling2009/gt-new-horizons:latest
COMPOSE := docker compose

.PHONY: build start stop remove

build:
	docker build -t $(IMAGE) .

start:
	$(COMPOSE) up -d

stop:
	$(COMPOSE) stop

remove:
	$(COMPOSE) down
