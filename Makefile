SHELL := bash -euo pipefail

.PHONY: local-image

local-image:
	./devel/start-localhost-registry || true
	./devel/build
	
	# Don't pull base-builder image since it's huge and not needed for local
	# inspection most of the time.
	docker image pull localhost:5000/nextstrain/base:latest
	
	./devel/stop-localhost-registry
