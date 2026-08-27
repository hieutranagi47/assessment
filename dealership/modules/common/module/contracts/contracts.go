// Package contracts holds cross-module contracts separately from module to
// preserve the dependency direction of module implementations.
package contracts

import "assessment/modules/auth/api/module/client"

// Contracts contains the narrow cross-module capabilities published by
// bounded contexts.
type Contracts struct{ Auth client.Authenticator }

// Verify checks cross-module contracts. Implementations may add startup
// validation as the published capabilities grow.
func (c *Contracts) Verify() error { return nil }
