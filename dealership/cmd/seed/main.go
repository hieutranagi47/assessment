// Command seed loads deterministic development data. It is deliberately
// separate from the HTTP service so neither startup nor tests alter a database.
package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"assessment/modules/common/config"
	"assessment/modules/seed"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx := context.Background()
	appConfig, err := config.Load()
	if err != nil {
		log.Fatal(err)
	}
	database, err := pgxpool.New(ctx, appConfig.PostgresDSN)
	if err != nil {
		log.Fatal("connect PostgreSQL: ", err)
	}
	defer database.Close()
	if err := seed.Run(ctx, database, appConfig.EmailLookupKey, os.Getenv("SEED_PASSWORD")); err != nil {
		log.Fatal(err)
	}
	fmt.Println("deterministic development seed data is ready")
}
