package main

import (
	"context"
	"log"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	authservice "assessment"
	appconfig "assessment/modules/common/config"
	commonlog "assessment/modules/common/log"

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
	poolConfig, err := pgxpool.ParseConfig(config.PostgresDSN)
	if err != nil {
		log.Fatal(err)
	}
	poolConfig.MaxConnLifetime = 3 * time.Minute
	poolConfig.MaxConns = 10
	database, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		log.Fatal(err)
	}

	service, err := authservice.New(ctx, database, config)
	if err != nil {
		log.Fatal(err)
	}
	defer service.Close()

	if err := service.Run(ctx, config.HTTPPort, config.HTTPSPort); err != nil {
		log.Fatal(err)
	}
}
