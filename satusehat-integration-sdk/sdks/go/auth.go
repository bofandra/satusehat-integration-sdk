package satusehat

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type tokenProvider struct {
	cfg       Config
	client    *http.Client
	mu        sync.Mutex
	token     string
	expiresAt time.Time
}

func (t *tokenProvider) invalidate() {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.token = ""
	t.expiresAt = time.Time{}
}
func (t *tokenProvider) get(ctx context.Context) (string, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.token != "" && time.Now().Before(t.expiresAt.Add(-60*time.Second)) {
		return t.token, nil
	}
	form := url.Values{"client_id": {t.cfg.ClientID}, "client_secret": {t.cfg.ClientSecret}}
	req, err := http.NewRequestWithContext(ctx, "POST", t.cfg.OAuthBaseURL()+"/accesstoken?grant_type=client_credentials", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := t.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return "", fmt.Errorf("oauth http %d: %s", resp.StatusCode, string(b))
	}
	var obj struct {
		AccessToken string      `json:"access_token"`
		ExpiresIn   interface{} `json:"expires_in"`
	}
	if err = json.Unmarshal(b, &obj); err != nil {
		return "", err
	}
	if obj.AccessToken == "" {
		return "", fmt.Errorf("oauth response missing access_token")
	}
	sec := 300
	switch v := obj.ExpiresIn.(type) {
	case string:
		fmt.Sscanf(v, "%d", &sec)
	case float64:
		sec = int(v)
	}
	t.token = obj.AccessToken
	t.expiresAt = time.Now().Add(time.Duration(sec) * time.Second)
	return t.token, nil
}
