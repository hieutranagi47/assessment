package http

import (
	"encoding/json"
	"fmt"
)

const (
	maxBodyLogBytes  = 512
	maxArrayLogItems = 6
)

// truncateBodyForLog bounds log volume while preserving useful JSON structure
// and the beginning/end of non-JSON payloads.
func truncateBodyForLog(body string) string {
	if len(body) <= maxBodyLogBytes {
		return body
	}
	var parsed any
	if json.Unmarshal([]byte(body), &parsed) != nil {
		return headTailTruncate(body)
	}
	if array, ok := parsed.([]any); ok && len(array) > maxArrayLogItems {
		parsed = truncateArray(array)
	}
	truncateJSONArrays(parsed)
	result, err := json.Marshal(parsed)
	if err != nil {
		return headTailTruncate(body)
	}
	return string(result)
}

// truncateJSONArrays recursively bounds arrays nested inside JSON objects.
func truncateJSONArrays(value any) {
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			if array, ok := child.([]any); ok && len(array) > maxArrayLogItems {
				typed[key] = truncateArray(array)
				truncateJSONArrays(typed[key])
			} else {
				truncateJSONArrays(child)
			}
		}
	case []any:
		for _, child := range typed {
			truncateJSONArrays(child)
		}
	}
}

// truncateArray keeps a prefix and the final item, replacing the middle with a count.
func truncateArray(array []any) []any {
	keep := maxArrayLogItems - 1
	result := make([]any, 0, keep+2)
	result = append(result, array[:keep]...)
	result = append(result, map[string]any{"...": fmt.Sprintf("%d items truncated", len(array)-keep-1)})
	return append(result, array[len(array)-1])
}

// headTailTruncate preserves both ends of an opaque payload within the log limit.
func headTailTruncate(value string) string {
	half := maxBodyLogBytes / 2
	return value[:half] + fmt.Sprintf(" ... (%d bytes truncated) ... ", len(value)-2*half) + value[len(value)-half:]
}
