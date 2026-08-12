package satusehat

import (
	"context"
	"math"
	"math/rand"
	"net/http"
	"strconv"
	"sync"
	"time"
)

type limiter struct {
	mu       sync.Mutex
	interval time.Duration
	last     time.Time
}

func (l *limiter) wait() {
	l.mu.Lock()
	defer l.mu.Unlock()
	if !l.last.IsZero() {
		if d := time.Until(l.last.Add(l.interval)); d > 0 {
			time.Sleep(d)
		}
	}
	l.last = time.Now()
}

type SDK struct {
	Config Config
	queue  *sqliteQueue
	tokens *tokenProvider
	fhir   *fhirClient
	limit  *limiter
}

func New(c Config) (*SDK, error) {
	if c.ProcessingTimeoutSec == 0 {
		c.ProcessingTimeoutSec = 300
	}
	if err := c.Validate(); err != nil {
		return nil, err
	}
	q, err := newQueue(c.QueuePath, c.ProcessingTimeoutSec)
	if err != nil {
		return nil, err
	}
	hc := &http.Client{Timeout: time.Duration(c.TimeoutSeconds) * time.Second}
	t := &tokenProvider{cfg: c, client: hc}
	return &SDK{Config: c, queue: q, tokens: t, fhir: &fhirClient{cfg: c, http: hc, tokens: t}, limit: &limiter{interval: time.Minute / time.Duration(c.RateLimitRPM)}}, nil
}
func (s *SDK) Close() error { return s.queue.close() }
func (s *SDK) Enqueue(op, rt, id string, payload []byte) (string, error) {
	return s.queue.enqueue(s.Config.OrganizationID, op, rt, id, payload, "")
}
func (s *SDK) EnqueueIdempotent(op, rt, id string, payload []byte, idempotencyKey string) (string, error) {
	return s.queue.enqueue(s.Config.OrganizationID, op, rt, id, payload, idempotencyKey)
}
func (s *SDK) QueueStats() (map[EventStatus]int, error) {
	return s.queue.stats()
}
func (s *SDK) DeadLetters(limit int) ([]Event, error) {
	return s.queue.deadLetters(limit)
}
func (s *SDK) Requeue(eventID string) (bool, error) {
	return s.queue.requeue(eventID)
}
func (s *SDK) Request(ctx context.Context, op, rt, id string, payload []byte) (FHIRResponse, error) {
	var last FHIRResponse
	var err error
	for a := 1; a <= s.Config.MaxRetries; a++ {
		s.limit.wait()
		last, err = s.fhir.requestOnce(ctx, op, rt, id, payload)
		if err != nil {
			if a == s.Config.MaxRetries {
				return last, err
			}
			time.Sleep(s.backoff(a, ""))
			continue
		}
		if last.StatusCode == 401 {
			s.tokens.invalidate()
		}
		_, retry := ClassifyHTTP(last.StatusCode)
		if !retry || a == s.Config.MaxRetries {
			return last, nil
		}
		time.Sleep(s.backoff(a, last.Headers["Retry-After"]))
	}
	return last, err
}
func (s *SDK) ProcessOnce(ctx context.Context, limit int) (int, error) {
	events, err := s.queue.ready(limit)
	if err != nil {
		return 0, err
	}
	for _, e := range events {
		a, err := s.queue.markProcessing(e.EventID)
		if err != nil {
			return 0, err
		}
		s.limit.wait()
		r, err := s.fhir.requestOnce(ctx, e.Operation, e.ResourceType, e.ResourceID, byteOrNil(e.PayloadJSON))
		if err != nil {
			if err = s.schedule(e.EventID, a, "transport_error", err.Error(), nil, ""); err != nil {
				return 0, err
			}
			continue
		}
		if err = s.apply(e.EventID, a, r); err != nil {
			return 0, err
		}
	}
	return len(events), nil
}
func byteOrNil(s string) []byte {
	if s == "" {
		return nil
	}
	return []byte(s)
}
func (s *SDK) apply(id string, a int, r FHIRResponse) error {
	status := r.StatusCode
	cat, retry := ClassifyHTTP(status)
	if status >= 200 && status <= 299 {
		return s.queue.complete(id, Success, &status, "", "", "")
	}
	if status == 401 {
		s.tokens.invalidate()
	}
	if retry {
		target := Retrying
		if status == 429 {
			target = RateLimited
		}
		return s.scheduleTarget(id, a, cat, string(r.Body), &status, r.Headers["Retry-After"], target)
	}
	return s.queue.complete(id, WaitingForCorrection, &status, cat, string(r.Body), "")
}
func (s *SDK) schedule(id string, a int, cat, msg string, hs *int, retryAfter string) error {
	return s.scheduleTarget(id, a, cat, msg, hs, retryAfter, Retrying)
}
func (s *SDK) scheduleTarget(id string, a int, cat, msg string, hs *int, retryAfter string, target EventStatus) error {
	if a >= s.Config.MaxRetries {
		return s.queue.complete(id, DeadLetter, hs, cat, msg, "")
	}
	next := time.Now().UTC().Add(s.backoff(a, retryAfter)).Format(time.RFC3339Nano)
	return s.queue.complete(id, target, hs, cat, msg, next)
}
func (s *SDK) backoff(a int, retryAfter string) time.Duration {
	if retryAfter != "" {
		if sec, e := strconv.ParseFloat(retryAfter, 64); e == nil && sec >= 0 {
			return time.Duration(sec * float64(time.Second))
		}
	}
	base := float64(s.Config.InitialBackoffMS) * math.Pow(2, float64(max(0, a-1)))
	if base > float64(s.Config.MaxBackoffMS) {
		base = float64(s.Config.MaxBackoffMS)
	}
	j := rand.Float64() * math.Min(1000, base*.2)
	return time.Duration(base+j) * time.Millisecond
}
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
