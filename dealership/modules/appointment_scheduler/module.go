package appointment_scheduler

import (
	"context"
	"embed"
	"fmt"

	"assessment/modules/appointment_scheduler/adapters/db"
	appointmenthttp "assessment/modules/appointment_scheduler/api/http"
	"assessment/modules/appointment_scheduler/app"
	"assessment/modules/common"
	"assessment/modules/common/module"
	"assessment/modules/common/module/contracts"
	"assessment/modules/common/observability"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Module struct {
	database *pgxpool.Pool
	handler  *appointmenthttp.Handler
}

func NewModule(database *pgxpool.Pool) *Module { return &Module{database: database} }
func (m *Module) Name() module.Name            { return "appointment_scheduler" }

//go:embed adapters/db/migrations/*.sql
var migrations embed.FS

func (m *Module) Init(ctx context.Context) error {
	return common.MigrateDatabaseUp(ctx, m.database, "appointment_scheduler", migrations, "adapters/db/migrations")
}

func (m *Module) RegisterHttp(ctx context.Context, router common.EchoRouter) error {
	if m.handler == nil {
		return fmt.Errorf("appointment scheduler module is not initialized with auth contract")
	}
	return appointmenthttp.Register(ctx, router, m.handler)
}
func (m *Module) RegisterContracts(_ context.Context, c *contracts.Contracts) error {
	if c.Auth == nil {
		return fmt.Errorf("auth contract is required by appointment scheduler")
	}
	repository := db.NewDealershipRepository(m.database)
	telemetry, err := observability.NewAppointmentSchedulerTelemetry()
	if err != nil {
		return fmt.Errorf("configure appointment scheduler telemetry: %w", err)
	}
	service := app.NewService(repository, c.Auth, telemetry)
	scheduleQuery := app.NewTechnicianScheduleQuery(repository)
	availableServiceBaysQuery := app.NewAvailableServiceBaysQuery(repository)
	m.handler = appointmenthttp.NewHandler(service, c.Auth, scheduleQuery)
	m.handler.SetAvailableServiceBayLister(availableServiceBaysQuery)
	return nil
}
