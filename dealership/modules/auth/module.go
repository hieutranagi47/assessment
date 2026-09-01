package auth

import (
	"context"
	"embed"

	"assessment/modules/auth/adapters/db"
	"assessment/modules/auth/adapters/password"
	"assessment/modules/auth/adapters/token"
	"assessment/modules/auth/api/http"
	authmodule "assessment/modules/auth/api/module"
	"assessment/modules/auth/app"
	"assessment/modules/common"
	"assessment/modules/common/module"
	"assessment/modules/common/module/contracts"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Module owns the standalone service's authentication boundary. Its HTTP
// surface is limited to /auth/**.
type Module struct {
	database *pgxpool.Pool
	config   Config
	handler  *http.Handler
	service  *app.Service
}

var _ module.Module = (*Module)(nil)

type Config struct {
	EmailEncryptionKey string
	EmailLookupKey     string
	JWTPrivateKeyPEM   []byte
	JWTPublicKeyPEM    []byte
}

// NewModule creates the auth module. Initialization is deferred until Init so
// the composition root can construct all modules before starting them.
func NewModule(database *pgxpool.Pool, config Config) *Module {
	return &Module{database: database, config: config}
}

// Name identifies this bounded context to the module lifecycle.
func (m *Module) Name() module.Name { return "auth" }

//go:embed adapters/db/migrations/*.sql
var migrations embed.FS

func (m *Module) Init(ctx context.Context) error {
	repository := db.NewRepository(m.database, m.config.EmailEncryptionKey, m.config.EmailLookupKey)
	issuer, err := token.NewIssuer(m.config.JWTPrivateKeyPEM, m.config.JWTPublicKeyPEM)
	if err != nil {
		return err
	}
	m.service = app.NewService(repository, issuer, password.BcryptHasher{})
	m.handler = http.NewHandler(m.service)
	return common.MigrateDatabaseUp(ctx, m.database, "auth", migrations, "adapters/db/migrations")
}

// RegisterHttp attaches the auth handler and its middleware to the router.
func (m *Module) RegisterHttp(ctx context.Context, e common.EchoRouter) error {
	return http.Register(ctx, e, m.handler)
}

// RegisterContracts publishes auth's narrow access-token authentication
// contract for modules that need to authorize their own requests.
func (m *Module) RegisterContracts(_ context.Context, c *contracts.Contracts) error {
	c.Auth = authmodule.New(m.service)
	return nil
}
