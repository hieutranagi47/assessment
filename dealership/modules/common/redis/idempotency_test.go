package redis

import (
	"context"
	"testing"
	"time"

	redisclient "github.com/redis/go-redis/v9"
)

type idempotencyClientStub struct {
	key        string
	value      any
	expiration time.Duration
	reserved   bool
	deletedKey string
}

func (s *idempotencyClientStub) SetNX(_ context.Context, key string, value any, expiration time.Duration) *redisclient.BoolCmd {
	s.key = key
	s.value = value
	s.expiration = expiration
	return redisclient.NewBoolResult(s.reserved, nil)
}

func (s *idempotencyClientStub) Del(_ context.Context, keys ...string) *redisclient.IntCmd {
	s.deletedKey = keys[0]
	return redisclient.NewIntResult(1, nil)
}

func TestIdempotencyStore(t *testing.T) {
	t.Parallel()
	client := &idempotencyClientStub{reserved: true}
	store := NewIdempotencyStore(client)

	reserved, err := store.Reserve(t.Context(), "idempotency:POST:/appointments:request-1")
	if err != nil {
		t.Fatalf("Reserve() error = %v", err)
	}
	if !reserved {
		t.Fatal("Reserve() = false, want true")
	}
	if client.value != "completed" {
		t.Errorf("stored value = %v, want completed", client.value)
	}
	if client.expiration != idempotencyKeyTTL {
		t.Errorf("expiration = %s, want %s", client.expiration, idempotencyKeyTTL)
	}

	if err := store.Release(t.Context(), client.key); err != nil {
		t.Fatalf("Release() error = %v", err)
	}
	if client.deletedKey != client.key {
		t.Errorf("deleted key = %q, want %q", client.deletedKey, client.key)
	}
}
