package http

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestTruncateBodyForLogKeepsShortAndOpaquePayloadsSafe(t *testing.T) {
	require.Equal(t, "short", truncateBodyForLog("short"))

	body := strings.Repeat("a", maxBodyLogBytes+100)
	truncated := truncateBodyForLog(body)
	require.Contains(t, truncated, "100 bytes truncated")
	require.True(t, strings.HasPrefix(truncated, strings.Repeat("a", maxBodyLogBytes/2)))
	require.True(t, strings.HasSuffix(truncated, strings.Repeat("a", maxBodyLogBytes/2)))
}

func TestTruncateBodyForLogBoundsTopLevelAndNestedJSONArrays(t *testing.T) {
	body, err := json.Marshal(map[string]any{
		"items":   []int{1, 2, 3, 4, 5, 6, 7, 8},
		"nested":  map[string]any{"items": []int{1, 2, 3, 4, 5, 6, 7}},
		"padding": strings.Repeat("x", maxBodyLogBytes),
	})
	require.NoError(t, err)
	truncated := truncateBodyForLog(string(body))
	var parsed map[string]any
	require.NoError(t, json.Unmarshal([]byte(truncated), &parsed))
	require.Len(t, parsed["items"], maxArrayLogItems+1)
	nested := parsed["nested"].(map[string]any)
	require.Len(t, nested["items"], maxArrayLogItems+1)
	require.Equal(t, float64(8), parsed["items"].([]any)[maxArrayLogItems].(float64))
}

func TestTruncateArrayKeepsPrefixMarkerAndFinalValue(t *testing.T) {
	values := []any{"a", "b", "c", "d", "e", "f", "g", "last"}
	result := truncateArray(values)
	require.Equal(t, []any{"a", "b", "c", "d", "e"}, result[:5])
	require.Equal(t, "2 items truncated", result[5].(map[string]any)["..."])
	require.Equal(t, "last", result[6])
}
