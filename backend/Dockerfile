FROM golang:1.25.12-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_TIME=unknown

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w \
      -X github.com/londxz/HackatonYandex/backend/internal/buildinfo.Version=${VERSION} \
      -X github.com/londxz/HackatonYandex/backend/internal/buildinfo.Commit=${COMMIT} \
      -X github.com/londxz/HackatonYandex/backend/internal/buildinfo.BuildTime=${BUILD_TIME}" \
    -o /out/razgovor-api ./cmd/api

FROM alpine:3.22

RUN apk add --no-cache ca-certificates \
    && addgroup -S app \
    && adduser -S -G app -u 10001 app

COPY --from=build /out/razgovor-api /usr/local/bin/razgovor-api

USER app
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/razgovor-api"]
