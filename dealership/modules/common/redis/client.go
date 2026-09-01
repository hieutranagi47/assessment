// Package redis owns shared Redis client initialization for the service.
package redis

import (
	"context"
	"fmt"

	redisclient "github.com/redis/go-redis/v9"
)

// NewClient parses the configured connection URL and verifies that Redis is
// reachable before exposing the client to the composition root.
func NewClient(ctx context.Context, url string) (*redisclient.Client, error) {
	options, err := redisclient.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("parse Redis URL: %w", err)
	}
	client := redisclient.NewClient(options)
	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("connect Redis: %w", err)
	}
	return client, nil
}
