package satusehat

import "testing"

func TestClassify(t *testing.T) {
	if c, r := ClassifyHTTP(429); c != "rate_limited" || !r {
		t.Fatal(c, r)
	}
	if c, r := ClassifyHTTP(422); c != "validation_error" || r {
		t.Fatal(c, r)
	}
}
