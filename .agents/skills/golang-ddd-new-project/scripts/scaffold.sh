#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 project <target-directory> <go-module-path> <first-module> [--template-root <services/auth>]" >&2
  echo "       $0 module <project-directory> <module-name>" >&2
  exit 2
}

valid_name() { [[ "$1" =~ ^[a-z][a-z0-9_]*$ ]]; }

write_module() {
  local project_dir="$1" name="$2" module_path package_path
  valid_name "$name" || { echo "module name must be lowercase snake_case: $name" >&2; exit 2; }
  module_path="$(cd "$project_dir" && go list -m -f '{{.Path}}')"
  package_path="$module_path/$name"
  [[ ! -e "$project_dir/$name" ]] || { echo "module already exists: $project_dir/$name" >&2; exit 1; }
  mkdir -p "$project_dir/$name"/{app,domain,api/http,adapters}

  cat > "$project_dir/$name/module.go" <<EOF
package $name

import (
    "context"

    "${module_path}/common"
    "${module_path}/common/module"
    "${module_path}/common/module/contracts"
    modulehttp "${package_path}/api/http"
    "${package_path}/app"
)

type Module struct { handler *modulehttp.Handler }

var _ module.Module = (*Module)(nil)

func NewModule() *Module { return &Module{} }
func (m *Module) Name() module.Name { return "$name" }
func (m *Module) Init(context.Context) error { m.handler = modulehttp.NewHandler(app.NewService()); return nil }
func (m *Module) RegisterContracts(context.Context, *contracts.Contracts) error { return nil }
func (m *Module) RegisterHttp(ctx context.Context, router common.EchoRouter) error { return modulehttp.Register(ctx, router, m.handler) }
EOF

  cat > "$project_dir/$name/app/service.go" <<EOF
package app

type Service struct{}
func NewService() *Service { return &Service{} }
func (s *Service) Health() string { return "$name is healthy" }
EOF

  cat > "$project_dir/$name/domain/entity.go" <<EOF
package domain

// Entity is a starting point for the module's invariant-owning aggregate.
// Replace it with a business-named type before adding persistence.
type Entity struct { id string }
func NewEntity(id string) Entity { return Entity{id: id} }
func (e Entity) ID() string { return e.id }
EOF

  cat > "$project_dir/$name/api/http/handler.go" <<EOF
package http

import (
    "context"
    stdhttp "net/http"

    "${module_path}/common"
    "${package_path}/app"
    echo "github.com/labstack/echo/v5"
)

type Handler struct { service *app.Service }
func NewHandler(service *app.Service) *Handler { return &Handler{service: service} }
func Register(_ context.Context, router common.EchoRouter, handler *Handler) error { router.GET("/$name/health", handler.health); return nil }
func (h *Handler) health(c *echo.Context) error { return c.JSON(stdhttp.StatusOK, map[string]string{"message": h.service.Health()}) }
EOF
}

command="${1:-}"; shift || true
case "$command" in
  project)
    [[ $# -ge 3 ]] || usage
    target="$1"; import_path="$2"; first_module="$3"; shift 3
    template_root=""
    if [[ "${1:-}" == "--template-root" && -n "${2:-}" ]]; then template_root="$2"; shift 2; fi
    [[ $# -eq 0 ]] || usage
    [[ ! -e "$target" ]] || { echo "target already exists: $target" >&2; exit 1; }
    valid_name "$first_module" || { echo "module name must be lowercase snake_case: $first_module" >&2; exit 2; }
    if [[ -z "$template_root" ]]; then
      repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      template_root="$repo_root/services/auth"
    fi
    [[ -d "$template_root/common" ]] || { echo "missing auth common template: $template_root/common" >&2; exit 1; }
    mkdir -p "$target"; cp -R "$template_root/common" "$target/common"
    cat > "$target/AGENTS.md" <<'EOF'
# API error contract

- Keep command and query errors transport-agnostic. Return `common.Error` for
  known client-safe errors, or stable sentinel/typed errors that the HTTP port
  maps explicitly.
- Map every HTTP error to the OpenAPI response
  `{"message": string, "slug": string, "details": ErrorDetail[]}`. Emit an
  empty `details` array when needed; never return `err.Error()` or expose
  `InternalError`.
- Define the response and details in OpenAPI, regenerate types, and test both
  structured and unknown-error fallback responses.
EOF
    (cd "$target" && go mod init "$import_path")
    find "$target/common" -name '*.go' -exec perl -0pi -e "s#github\\.com/hieutranagi47/auth#${import_path//\//\\/}#g" {} +
    write_module "$target" "$first_module"
    cat > "$target/service.go" <<EOF
package service

import (
    "context"
    "fmt"
    "time"

    commonhttp "${import_path}/common/http"
    "${import_path}/common/log"
    "${import_path}/common/module"
    "${import_path}/common/module/contracts"
    echo "github.com/labstack/echo/v5"
)

type Service struct { router *echo.Echo; modules []module.Module }
func New(ctx context.Context, modules ...module.Module) (*Service, error) {
    router := commonhttp.NewEcho(); moduleContracts := &contracts.Contracts{}
    for _, current := range modules {
        started := time.Now()
        if err := current.Init(ctx); err != nil { return nil, fmt.Errorf("initialize module %s: %w", current.Name(), err) }
        if err := current.RegisterContracts(ctx, moduleContracts); err != nil { return nil, fmt.Errorf("register module %s contracts: %w", current.Name(), err) }
        log.FromContext(ctx).With("module", current.Name(), "duration", time.Since(started)).Debug("Initialized module")
    }
    if err := moduleContracts.Verify(); err != nil { return nil, fmt.Errorf("verify module contracts: %w", err) }
    for _, current := range modules { if err := current.RegisterHttp(ctx, router); err != nil { return nil, fmt.Errorf("register module %s HTTP routes: %w", current.Name(), err) } }
    return &Service{router: router, modules: modules}, nil
}
func (s *Service) Router() *echo.Echo { return s.router }
EOF
    mkdir -p "$target/cmd"
    cat > "$target/cmd/main.go" <<EOF
package main

import (
    "context"
    stdlog "log"
    "log/slog"
    stdhttp "net/http"
    "os"
    "os/signal"
    "syscall"

    service "${import_path}"
    "${import_path}/common/log"
    "${import_path}/${first_module}"
)

func main() {
    log.Init(slog.LevelInfo)
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM); defer stop()
    app, err := service.New(ctx, ${first_module}.NewModule()); if err != nil { stdlog.Fatal(err) }
    server := &stdhttp.Server{Addr: ":8080", Handler: app.Router()}
    go func() { <-ctx.Done(); _ = server.Shutdown(context.Background()) }()
    stdlog.Fatal(server.ListenAndServe())
}
EOF
    (cd "$target" && go mod tidy && gofmt -w . && go test ./...)
    echo "created $target; start it with: cd $target && go run ./cmd"
    ;;
  module)
    [[ $# -eq 2 ]] || usage
    [[ -f "$1/go.mod" ]] || { echo "not a Go project: $1" >&2; exit 1; }
    write_module "$1" "$2"
    (cd "$1" && gofmt -w "$2" && go test ./...)
    echo "created module $2; add $2.NewModule() to cmd/main.go's service.New call"
    ;;
  *) usage ;;
esac
