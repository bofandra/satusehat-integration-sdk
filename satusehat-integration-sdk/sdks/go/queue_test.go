package satusehat

import (
	"os"
	"testing"
)

func TestQueue(t *testing.T) {
	p := t.TempDir() + "/q.db"
	c := Config{ClientID: "x", ClientSecret: "y", OrganizationID: "1", Environment: "sandbox", QueuePath: p, TimeoutSeconds: 1, RateLimitRPM: 1000, MaxRetries: 5, InitialBackoffMS: 1, MaxBackoffMS: 10}
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
