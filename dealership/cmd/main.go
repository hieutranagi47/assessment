package main

import (
	"context"
	"fmt"
	"log"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	dealershipService "assessment"
	appconfig "assessment/modules/common/config"
	commonlog "assessment/modules/common/log"
	"assessment/modules/common/observability"
	commonredis "assessment/modules/common/redis"

	"github.com/exaring/otelpgx"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	commonlog.Init(slog.LevelInfo)
	config, err := appconfig.Load()
	if err != nil {
		log.Fatal(err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	providers, err := observability.Configure(
		ctx,
		config.OTELServiceName,
		config.OTELTraceEndpoint,
		config.ServiceVersion,
		config.Environment,
		config.DeploymentRegion,
	)
	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		if err := providers.Shutdown(context.Background()); err != nil {
			log.Printf("shutdown observability: %v", err)
		}
	}()
	poolConfig, err := pgxpool.ParseConfig(config.PostgresDSN)
	if err != nil {
		log.Fatal(err)
	}
	poolConfig.MaxConnLifetime = 3 * time.Minute
	poolConfig.MaxConns = 10
	poolConfig.ConnConfig.Tracer = otelpgx.NewTracer(
		otelpgx.WithTrimSQLInSpanName(),
		otelpgx.WithDisableSQLStatementInAttributes(),
	)
	database, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		log.Fatal(err)
	}
	if err := otelpgx.RecordStats(database); err != nil {
		log.Fatal(fmt.Errorf("register PostgreSQL pool metrics: %w", err))
	}
	redisClient, err := commonredis.NewClient(ctx, config.RedisURL)
	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		if err := redisClient.Close(); err != nil {
			log.Printf("close Redis: %v", err)
		}
	}()

	idempotencyStore := commonredis.NewIdempotencyStore(redisClient)
	service, err := dealershipService.New(ctx, database, idempotencyStore, config)
	if err != nil {
		log.Fatal(err)
	}
	defer service.Close()

	if err := service.Run(ctx, config.HTTPPort, config.HTTPSPort); err != nil {
		log.Fatal(err)
	}
}
