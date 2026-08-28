package http

import (
	"embed"
	"net/http"

	"assessment/modules/common"

	echo "github.com/labstack/echo/v5"
)

// The OpenAPI document is embedded into the service binary so the docs work
// in containers and deployed environments without mounting the source tree.
//
//go:embed openapi.yaml
var openAPIFS embed.FS

const swaggerUIHTML = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Appointment Scheduler API</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.11.10/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.11.10/swagger-ui-bundle.js"></script>
  <script>
    window.onload = () => {
      window.ui = SwaggerUIBundle({
        url: "./openapi.yaml",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [SwaggerUIBundle.presets.apis],
        layout: "BaseLayout"
      });
    };
  </script>
</body>
</html>`

// RegisterDocs exposes the interactive API documentation and its embedded
// OpenAPI contract. The module owns both its API routes and documentation.
func RegisterDocs(router common.EchoRouter) {
	router.GET("/appointment-scheduler/docs", func(c *echo.Context) error {
		return c.Redirect(http.StatusTemporaryRedirect, "/appointment-scheduler/docs/")
	})
	router.GET("/appointment-scheduler/docs/", func(c *echo.Context) error {
		return c.HTML(http.StatusOK, swaggerUIHTML)
	})
	router.GET("/appointment-scheduler/docs/openapi.yaml", func(c *echo.Context) error {
		spec, err := openAPIFS.ReadFile("openapi.yaml")
		if err != nil {
			return err
		}
		return c.Blob(http.StatusOK, "application/yaml; charset=utf-8", spec)
	})
}
