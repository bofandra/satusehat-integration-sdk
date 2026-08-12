package satusehat

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"strings"
)

type fhirClient struct {
	cfg    Config
	http   *http.Client
	tokens *tokenProvider
}

func (f *fhirClient) requestOnce(ctx context.Context, method, rt, id string, payload []byte) (FHIRResponse, error) {
	u := f.cfg.FHIRBaseURL() + "/" + rt
	if id != "" {
		u += "/" + id
	}
	var body io.Reader
	if payload != nil {
		body = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, strings.ToUpper(method), u, body)
	if err != nil {
		return FHIRResponse{}, err
	}
	tok, err := f.tokens.get(ctx)
	if err != nil {
		return FHIRResponse{}, err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Accept", "application/fhir+json, application/json")
	ct := "application/fhir+json"
	if strings.EqualFold(method, "PATCH") {
		ct = "application/json"
	}
	req.Header.Set("Content-Type", ct)
	resp, err := f.http.Do(req)
	if err != nil {
		return FHIRResponse{}, err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return FHIRResponse{}, err
	}
	h := map[string]string{}
	for k, v := range resp.Header {
		if len(v) > 0 {
			h[k] = v[0]
		}
	}
	return FHIRResponse{StatusCode: resp.StatusCode, Body: b, Headers: h}, nil
}
