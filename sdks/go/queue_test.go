package satusehat

import (
	"os"
	"testing"
)

func TestQueue(t *testing.T) {
	p := t.TempDir() + "/q.db"
	c := Config{ClientID: "x", ClientSecret: "y", OrganizationID: "1", Environment: "sandbox", QueuePath: p, TimeoutSeconds: 1, RateLimitRPM: 1000, MaxRetries: 5, ProcessingTimeoutSec: 300, InitialBackoffMS: 1, MaxBackoffMS: 10}
	s, e := New(c)
	if e != nil {
		t.Fatal(e)
	}
	defer s.Close()
	id, e := s.Enqueue("POST", "Encounter", "", []byte(`{"resourceType":"Encounter"}`))
	if e != nil || id == "" {
		t.Fatal(id, e)
	}
	_ = os.Remove(p)
}

func TestIdempotentEnqueueReturnsExistingEvent(t *testing.T) {
	p := t.TempDir() + "/q.db"
	c := Config{ClientID: "x", ClientSecret: "y", OrganizationID: "1", Environment: "sandbox", QueuePath: p, TimeoutSeconds: 1, RateLimitRPM: 1000, MaxRetries: 5, ProcessingTimeoutSec: 300, InitialBackoffMS: 1, MaxBackoffMS: 10}
	s, err := New(c)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	first, err := s.EnqueueIdempotent("POST", "Encounter", "", []byte(`{"resourceType":"Encounter"}`), "visit-1:create")
	if err != nil {
		t.Fatal(err)
	}
	second, err := s.EnqueueIdempotent("POST", "Encounter", "", []byte(`{"resourceType":"Encounter"}`), "visit-1:create")
	if err != nil {
		t.Fatal(err)
	}
	if first != second {
		t.Fatalf("expected duplicate enqueue to return %s, got %s", first, second)
	}
	stats, err := s.QueueStats()
	if err != nil {
		t.Fatal(err)
	}
	if stats[Queued] != 1 {
		t.Fatalf("expected 1 queued event, got %#v", stats)
	}
}

func TestDeadLetterAdminRequeue(t *testing.T) {
	p := t.TempDir() + "/q.db"
	q, err := newQueue(p, 300)
	if err != nil {
		t.Fatal(err)
	}
	defer q.close()
	id, err := q.enqueue("1", "POST", "Encounter", "", []byte(`{"resourceType":"Encounter"}`), "")
	if err != nil {
		t.Fatal(err)
	}
	status := 503
	if err := q.complete(id, DeadLetter, &status, "server_error", "failed", ""); err != nil {
		t.Fatal(err)
	}
	letters, err := q.deadLetters(10)
	if err != nil {
		t.Fatal(err)
	}
	if len(letters) != 1 || letters[0].EventID != id {
		t.Fatalf("expected dead letter %s, got %#v", id, letters)
	}
	ok, err := q.requeue(id)
	if err != nil {
		t.Fatal(err)
	}
	if !ok {
		t.Fatal("expected requeue to update the event")
	}
	stats, err := q.stats()
	if err != nil {
		t.Fatal(err)
	}
	if stats[Queued] != 1 || stats[DeadLetter] != 0 {
		t.Fatalf("unexpected stats after requeue: %#v", stats)
	}
}

func TestStaleProcessingEventsAreRecovered(t *testing.T) {
	p := t.TempDir() + "/q.db"
	q, err := newQueue(p, 300)
	if err != nil {
		t.Fatal(err)
	}
	defer q.close()
	id, err := q.enqueue("1", "POST", "Encounter", "", []byte(`{"resourceType":"Encounter"}`), "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = q.markProcessing(id); err != nil {
		t.Fatal(err)
	}
	if _, err = q.db.Exec(`UPDATE integration_events SET next_retry_at=? WHERE event_id=?`, "2000-01-01T00:00:00.000000000Z", id); err != nil {
		t.Fatal(err)
	}
	events, err := q.ready(10)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 1 || events[0].EventID != id {
		t.Fatalf("expected stale processing event %s, got %#v", id, events)
	}
}
