package satusehat

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

const (
	SandboxOAuth    = "https://api-satusehat-stg.dto.kemkes.go.id/oauth2/v1"
	SandboxFHIR     = "https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1"
	ProductionOAuth = "https://api-satusehat.kemkes.go.id/oauth2/v1"
	ProductionFHIR  = "https://api-satusehat.kemkes.go.id/fhir-r4/v1"
)

type Config struct {
	ClientID             string
	ClientSecret         string
	OrganizationID       string
	Environment          string
	QueuePath            string
	TimeoutSeconds       int
	RateLimitRPM         int
	MaxRetries           int
	ProcessingTimeoutSec int
	InitialBackoffMS     int
	MaxBackoffMS         int
	OAuthBaseURLOverride string
	FHIRBaseURLOverride  string
}

func (c Config) Validate() error {
	if c.Environment != "sandbox" && c.Environment != "production" {
		return fmt.Errorf("environment must be sandbox or production")
	}
	if c.ClientID == "" || c.ClientSecret == "" || c.OrganizationID == "" {
		return fmt.Errorf("client id, client secret, organization id are required")
	}
	if c.RateLimitRPM <= 0 || c.MaxRetries <= 0 || c.ProcessingTimeoutSec <= 0 {
		return fmt.Errorf("rate limit, max retries, and processing timeout must be > 0")
	}
	return nil
}
func (c Config) OAuthBaseURL() string {
	if c.OAuthBaseURLOverride != "" {
		return strings.TrimRight(c.OAuthBaseURLOverride, "/")
	}
	if c.Environment == "production" {
		return ProductionOAuth
	}
	return SandboxOAuth
}
func (c Config) FHIRBaseURL() string {
	if c.FHIRBaseURLOverride != "" {
		return strings.TrimRight(c.FHIRBaseURLOverride, "/")
	}
	if c.Environment == "production" {
		return ProductionFHIR
	}
	return SandboxFHIR
}
func envInt(k string, d int) int {
	if v := os.Getenv(k); v != "" {
		if i, e := strconv.Atoi(v); e == nil {
			return i
		}
	}
	return d
}
func ConfigFromEnv() (Config, error) {
	c := Config{ClientID: os.Getenv("SATUSEHAT_CLIENT_ID"), ClientSecret: os.Getenv("SATUSEHAT_CLIENT_SECRET"), OrganizationID: os.Getenv("SATUSEHAT_ORGANIZATION_ID"), Environment: strings.ToLower(os.Getenv("SATUSEHAT_ENV")), QueuePath: os.Getenv("SATUSEHAT_QUEUE_PATH"), TimeoutSeconds: envInt("SATUSEHAT_TIMEOUT_SECONDS", 30), RateLimitRPM: envInt("SATUSEHAT_RATE_LIMIT_RPM", 300), MaxRetries: envInt("SATUSEHAT_MAX_RETRIES", 5), ProcessingTimeoutSec: envInt("SATUSEHAT_PROCESSING_TIMEOUT_SECONDS", 300), InitialBackoffMS: envInt("SATUSEHAT_INITIAL_BACKOFF_MS", 1000), MaxBackoffMS: envInt("SATUSEHAT_MAX_BACKOFF_MS", 60000), OAuthBaseURLOverride: os.Getenv("SATUSEHAT_OAUTH_BASE_URL"), FHIRBaseURLOverride: os.Getenv("SATUSEHAT_FHIR_BASE_URL")}
	if c.Environment == "" {
		c.Environment = "sandbox"
	}
	if c.QueuePath == "" {
		c.QueuePath = "./satusehat-sdk.db"
	}
	return c, c.Validate()
}
