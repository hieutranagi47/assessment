package log

import (
	"log/slog"
	"os"
)

// Init configures the process-wide structured logger used by HTTP and modules.
func Init(level slog.Level) {
	slog.SetDefault(slog.New(NewHandler(os.Stderr, &Options{
		HandlerOptions: &slog.HandlerOptions{Level: level},
		TimeFormat:     "[15:04:05.000]",
	})))
}
