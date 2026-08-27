package log

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Options configures the human-readable slog handler used during development.
type Options struct {
	*slog.HandlerOptions
	TimeFormat string
	SortKeys   bool
	NoColor    bool
}

func NewHandler(out io.Writer, options *Options) slog.Handler {
	if out == nil {
		out = io.Discard
	}
	opts := Options{HandlerOptions: &slog.HandlerOptions{Level: slog.LevelInfo}, TimeFormat: "[15:04:05]"}
	if options != nil {
		opts.SortKeys, opts.NoColor = options.SortKeys, options.NoColor
		if options.TimeFormat != "" {
			opts.TimeFormat = options.TimeFormat
		}
		if options.HandlerOptions != nil {
			opts.HandlerOptions = options.HandlerOptions
		}
	}
	return &humanHandler{opts: opts, out: out, mu: new(sync.Mutex)}
}

type humanHandler struct {
	opts   Options
	out    io.Writer
	mu     *sync.Mutex
	groups []string
	attrs  []slog.Attr
}

func (h *humanHandler) Enabled(_ context.Context, level slog.Level) bool {
	return level >= h.opts.Level.Level()
}
func (h *humanHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	if len(attrs) == 0 {
		return h
	}
	clone := h.clone()
	clone.attrs = append(clone.attrs, attrs...)
	return clone
}
func (h *humanHandler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	clone := h.clone()
	clone.groups = append(clone.groups, name)
	return clone
}
func (h *humanHandler) Handle(_ context.Context, record slog.Record) error {
	var line strings.Builder
	line.WriteString(h.dim(record.Time.Format(h.opts.TimeFormat)))
	line.WriteByte(' ')
	line.WriteString(h.levelBadge(record.Level, record.Level.String()))
	line.WriteByte(' ')
	line.WriteString(record.Message)
	attrs := append([]slog.Attr(nil), h.attrs...)
	record.Attrs(func(attr slog.Attr) bool { attrs = append(attrs, attr); return true })
	if h.opts.SortKeys {
		sort.SliceStable(attrs, func(i, j int) bool { return attrs[i].Key < attrs[j].Key })
	}
	h.appendAttrs(&line, attrs, h.groups)
	line.WriteByte('\n')
	h.mu.Lock()
	defer h.mu.Unlock()
	_, err := io.WriteString(h.out, line.String())
	return err
}
func (h *humanHandler) clone() *humanHandler {
	clone := *h
	clone.groups = append([]string(nil), h.groups...)
	clone.attrs = append([]slog.Attr(nil), h.attrs...)
	return &clone
}
func (h *humanHandler) appendAttrs(line *strings.Builder, attrs []slog.Attr, groups []string) {
	for _, attr := range attrs {
		attr = h.replace(groups, attr)
		if attr.Key == "" {
			continue
		}
		attr.Value = attr.Value.Resolve()
		if attr.Value.Kind() == slog.KindGroup {
			h.appendAttrs(line, attr.Value.Group(), append(groups, attr.Key))
			continue
		}
		line.WriteByte(' ')
		line.WriteString(h.dim(strings.Join(append(append([]string(nil), groups...), attr.Key), ".") + "="))
		line.WriteString(formatValue(attr.Value))
	}
}
func (h *humanHandler) replace(groups []string, attr slog.Attr) slog.Attr {
	if h.opts.ReplaceAttr == nil {
		return attr
	}
	return h.opts.ReplaceAttr(groups, attr)
}
func (h *humanHandler) levelBadge(level slog.Level, text string) string {
	bg := "\x1b[42m"
	if level < slog.LevelInfo {
		bg = "\x1b[44m"
	} else if level < slog.LevelWarn {
		bg = "\x1b[42m"
	} else if level < slog.LevelError {
		bg = "\x1b[43m"
	} else {
		bg = "\x1b[41m"
	}
	return h.colour(bg+"\x1b[30m", " "+text+" ")
}
func (h *humanHandler) colour(prefix, value string) string {
	if h.opts.NoColor {
		return value
	}
	return prefix + value + "\x1b[0m"
}
func (h *humanHandler) dim(value string) string { return h.colour("\x1b[2m", value) }
func formatValue(value slog.Value) string {
	switch value.Kind() {
	case slog.KindString:
		text := value.String()
		if strings.ContainsAny(text, " \t\n=\"") || text == "" {
			return strconv.Quote(text)
		}
		return text
	case slog.KindInt64:
		return strconv.FormatInt(value.Int64(), 10)
	case slog.KindUint64:
		return strconv.FormatUint(value.Uint64(), 10)
	case slog.KindFloat64:
		return strconv.FormatFloat(value.Float64(), 'g', -1, 64)
	case slog.KindBool:
		return strconv.FormatBool(value.Bool())
	case slog.KindDuration:
		return value.Duration().String()
	case slog.KindTime:
		return value.Time().Format(time.RFC3339Nano)
	case slog.KindAny:
		return fmt.Sprint(value.Any())
	default:
		return value.String()
	}
}
