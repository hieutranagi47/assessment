FROM golang:1.26.5-alpine AS builder

WORKDIR /app
COPY dealership/go.mod dealership/go.sum ./
RUN go mod download

COPY dealership/ ./
RUN CGO_ENABLED=0 go build -o /app/dealership-service ./cmd
RUN CGO_ENABLED=0 go build -o /app/dealership-seed ./cmd/seed

FROM alpine:3.22
RUN apk add --no-cache tzdata \
	&& adduser -D -H -u 10001 dealership
WORKDIR /app
COPY --from=builder /app/dealership-service /app/dealership-service
COPY --from=builder /app/dealership-seed /app/dealership-seed
USER dealership
CMD ["/app/dealership-service"]
