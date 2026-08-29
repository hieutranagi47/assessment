// Package observability configures metrics and tracing at the application
// composition root.
package observability

import (
	"context"
	"errors"
	"fmt"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/prometheus"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	tracesdk "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.37.0"
)

// Providers owns the OpenTelemetry providers installed for this process.
type Providers struct {
	metrics *metric.MeterProvider
	traces  *tracesdk.TracerProvider
}

// Configure installs Prometheus metrics and, when traceEndpoint is present,
// OTLP/HTTP tracing. The Prometheus exporter registers with the default
// registry exposed through the application's /metrics endpoint.
func Configure(
	ctx context.Context,
	serviceName string,
	traceEndpoint string,
	serviceVersion string,
	environment string,
	deploymentRegion string,
) (*Providers, error) {
	resource := resource.NewWithAttributes(
		semconv.SchemaURL,
		semconv.ServiceName(serviceName),
		semconv.ServiceVersion(serviceVersion),
		attribute.String("deployment.environment.name", environment),
		attribute.String("cloud.region", deploymentRegion),
	)

	metricExporter, err := prometheus.New()
	if err != nil {
		return nil, fmt.Errorf("configure Prometheus exporter: %w", err)
	}
	metricProvider := metric.NewMeterProvider(
		metric.WithReader(metricExporter),
		metric.WithResource(resource),
	)

	traceProvider := tracesdk.NewTracerProvider(
		tracesdk.WithResource(resource),
	)
	if traceEndpoint != "" {
		traceExporter, err := otlptracehttp.New(
			ctx,
			otlptracehttp.WithEndpointURL(traceEndpoint),
		)
		if err != nil {
			_ = metricProvider.Shutdown(ctx)
			return nil, fmt.Errorf("configure OTLP trace exporter: %w", err)
		}
		traceProvider = tracesdk.NewTracerProvider(
			tracesdk.WithBatcher(traceExporter),
			tracesdk.WithResource(resource),
		)
	}

	otel.SetMeterProvider(metricProvider)
	otel.SetTracerProvider(traceProvider)
	otel.SetTextMapPropagator(propagation.TraceContext{})

	return &Providers{metrics: metricProvider, traces: traceProvider}, nil
}

// Shutdown flushes traces and releases OpenTelemetry provider resources.
func (p *Providers) Shutdown(ctx context.Context) error {
	if p == nil {
		return nil
	}
	return errors.Join(
		p.traces.Shutdown(ctx),
		p.metrics.Shutdown(ctx),
	)
}
