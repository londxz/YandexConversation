.PHONY: build check compose-down compose-logs compose-up fmt run test test-integration test-race vet

build:
	go build ./...

fmt:
	gofmt -w $$(find . -name '*.go' -not -path './vendor/*')

vet:
	go vet ./...

test:
	go test ./...

test-race:
	go test -race ./...

test-integration:
	@test -n "$(TEST_DATABASE_URL)"
	go test -race ./internal/repository/postgres -run Integration -count=1 -v

check: fmt vet test-race build

run:
	go run ./cmd/api

compose-up:
	docker compose up --build -d

compose-down:
	docker compose down

compose-logs:
	docker compose logs -f api
