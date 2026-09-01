package redis

import (
	"context"
	"time"

	commonHTTP "assessment/modules/common/http"

	redisclient "github.com/redis/go-redis/v9"
)

const idempotencyKeyTTL = 24 * time.Hour

type idempotencyClient interface {
	SetNX(context.Context, string, any, time.Duration) *redisclient.BoolCmd
	Del(context.Context, ...string) *redisclient.IntCmd
}

type idempotencyStore struct {
	client idempotencyClient
}

var _ commonHTTP.IdempotencyStore = (*idempotencyStore)(nil)

func NewIdempotencyStore(client idempotencyClient) commonHTTP.IdempotencyStore {
	if client == nil {
		panic("Redis idempotency client is required")
	}
	return &idempotencyStore{client: client}
}

// Reserve atomically records a key only when it is absent. The expiry bounds
// Redis memory usage and defines the period during which duplicate retries are rejected.
func (s *idempotencyStore) Reserve(ctx context.Context, key string) (bool, error) {
	return s.client.SetNX(ctx, key, "completed", idempotencyKeyTTL).Result()
}

func (s *idempotencyStore) Release(ctx context.Context, key string) error {
	return s.client.Del(ctx, key).Err()
}
