package http

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"assessment/modules/common"

	"github.com/stretchr/testify/require"
)

func TestRegisterDocs(t *testing.T) {
	router := common.NewEcho(common.EchoConfig{})
	RegisterDocs(router)

	tests := []struct {
		name             string
		path             string
		wantStatus       int
		wantContentType  string
		wantLocation     string
		wantBodyContains string
	}{
		{
			name:         "redirects to trailing slash",
			path:         "/appointment-scheduler/docs",
			wantStatus:   http.StatusTemporaryRedirect,
			wantLocation: "/appointment-scheduler/docs/",
		},
		{
			name:             "serves Swagger UI",
			path:             "/appointment-scheduler/docs/",
			wantStatus:       http.StatusOK,
			wantContentType:  "text/html; charset=UTF-8",
			wantBodyContains: "Appointment Scheduler API",
		},
		{
			name:             "serves embedded OpenAPI document",
			path:             "/appointment-scheduler/docs/openapi.yaml",
			wantStatus:       http.StatusOK,
			wantContentType:  "application/yaml; charset=utf-8",
			wantBodyContains: "format: date, pattern: '^\\d{4}-\\d{2}-\\d{2}$'",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, test.path, nil)
			recorder := httptest.NewRecorder()

			router.ServeHTTP(recorder, request)

			require.Equal(t, test.wantStatus, recorder.Code)
			if test.wantContentType != "" {
				require.Equal(t, test.wantContentType, recorder.Header().Get("Content-Type"))
			}
			if test.wantLocation != "" {
				require.Equal(t, test.wantLocation, recorder.Header().Get("Location"))
			}
			if test.wantBodyContains != "" {
				require.Contains(t, recorder.Body.String(), test.wantBodyContains)
			}
		})
	}
}
