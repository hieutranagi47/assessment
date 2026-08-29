package authservice

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"time"

	"assessment/modules/appointment_scheduler"
	"assessment/modules/auth"
	"assessment/modules/common/config"
	commonHTTP "assessment/modules/common/http"
	"assessment/modules/common/log"
	"assessment/modules/common/module"
	"assessment/modules/common/module/contracts"

	"github.com/jackc/pgx/v5/pgxpool"
	echo "github.com/labstack/echo/v5"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Service is the composition root for the standalone authentication service.
type Service struct {
	router  *echo.Echo
	db      *pgxpool.Pool
	modules []module.Module
	tls     *tls.Config
}

// New builds the composition root, initializes every module, verifies module
// contracts, and registers their HTTP routes.
func New(ctx context.Context, database *pgxpool.Pool, config config.Config) (*Service, error) {
	if database == nil {
		return nil, fmt.Errorf("PostgreSQL database is required")
	}
	tlsConfig, err := newTLSConfig([]byte(config.JWTPrivateKeyPEM), []byte(config.JWTPublicKeyPEM))
	if err != nil {
		return nil, fmt.Errorf("configure HTTPS: %w", err)
	}
	router := commonHTTP.NewEcho()
	modules := []module.Module{
		auth.NewModule(database, auth.Config{EmailEncryptionKey: config.EmailEncryptionKey, EmailLookupKey: config.EmailLookupKey, JWTPrivateKeyPEM: []byte(config.JWTPrivateKeyPEM), JWTPublicKeyPEM: []byte(config.JWTPublicKeyPEM)}),
		appointment_scheduler.NewModule(database),
	}
	moduleContracts := &contracts.Contracts{}
	for _, currentModule := range modules {
		started := time.Now()
		if err := currentModule.Init(ctx); err != nil {
			return nil, fmt.Errorf("initialize module %s: %w", currentModule.Name(), err)
		}
		if err := currentModule.RegisterContracts(ctx, moduleContracts); err != nil {
			return nil, fmt.Errorf("register module %s contracts: %w", currentModule.Name(), err)
		}
		log.FromContext(ctx).With("module", currentModule.Name(), "duration", time.Since(started)).Debug("Initialized module")
	}
	if err := moduleContracts.Verify(); err != nil {
		return nil, fmt.Errorf("verify module contracts: %w", err)
	}
	for _, currentModule := range modules {
		if err := currentModule.RegisterHttp(ctx, router); err != nil {
			return nil, fmt.Errorf("register module %s HTTP routes: %w", currentModule.Name(), err)
		}
	}
	return &Service{router: router, db: database, modules: modules, tls: tlsConfig}, nil
}

// Router returns the configured Echo router for embedding or testing.
func (s *Service) Router() *echo.Echo { return s.router }

// Close releases the service's database resources.
func (s *Service) Close() error {
	s.db.Close()
	return nil
}

// Run serves HTTP and HTTPS until the context is cancelled or one listener
// exits unexpectedly. HTTPS uses an in-memory certificate derived from the RSA
// key pair configured at the composition root.
func (s *Service) Run(ctx context.Context, httpPort, httpsPort string) error {
	tracedRouter := otelhttp.NewHandler(s.router, "dealership")
	httpServer := &http.Server{Addr: ":" + httpPort, Handler: tracedRouter, ReadHeaderTimeout: 5 * time.Second}
	httpsServer := &http.Server{Addr: ":" + httpsPort, Handler: tracedRouter, ReadHeaderTimeout: 5 * time.Second, TLSConfig: s.tls}
	errCh := make(chan error, 2)

	go func() { errCh <- httpServer.ListenAndServe() }()
	go func() { errCh <- httpsServer.ListenAndServeTLS("", "") }()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		return errors.Join(httpServer.Shutdown(shutdownCtx), httpsServer.Shutdown(shutdownCtx))
	case err := <-errCh:
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(shutdownCtx)
		_ = httpsServer.Shutdown(shutdownCtx)
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}

func newTLSConfig(privateKeyPEM, publicKeyPEM []byte) (*tls.Config, error) {
	privateKey, err := parseRSAPrivateKey(privateKeyPEM)
	if err != nil {
		return nil, err
	}
	publicKey, err := parseRSAPublicKey(publicKeyPEM)
	if err != nil {
		return nil, err
	}
	if privateKey.PublicKey.N.Cmp(publicKey.N) != 0 || privateKey.PublicKey.E != publicKey.E {
		return nil, errors.New("RSA private and public keys do not match")
	}

	now := time.Now()
	certificateTemplate := x509.Certificate{
		SerialNumber:          big.NewInt(now.UnixNano()),
		Subject:               pkix.Name{CommonName: "localhost"},
		NotBefore:             now.Add(-5 * time.Minute),
		NotAfter:              now.AddDate(1, 0, 0),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{"localhost"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
	}
	certificateDER, err := x509.CreateCertificate(rand.Reader, &certificateTemplate, &certificateTemplate, publicKey, privateKey)
	if err != nil {
		return nil, fmt.Errorf("create TLS certificate: %w", err)
	}

	return &tls.Config{
		MinVersion:   tls.VersionTLS12,
		Certificates: []tls.Certificate{{Certificate: [][]byte{certificateDER}, PrivateKey: privateKey}},
	}, nil
}

func parseRSAPrivateKey(value []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(value)
	if block == nil {
		return nil, errors.New("decode RSA private key PEM")
	}
	if privateKey, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return privateKey, nil
	}
	parsedKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse RSA private key: %w", err)
	}
	privateKey, ok := parsedKey.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("private key is not RSA")
	}
	return privateKey, nil
}

func parseRSAPublicKey(value []byte) (*rsa.PublicKey, error) {
	block, _ := pem.Decode(value)
	if block == nil {
		return nil, errors.New("decode RSA public key PEM")
	}
	parsedKey, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse RSA public key: %w", err)
	}
	publicKey, ok := parsedKey.(*rsa.PublicKey)
	if !ok {
		return nil, errors.New("public key is not RSA")
	}
	return publicKey, nil
}
