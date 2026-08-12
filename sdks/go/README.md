# Go SDK

Requires Go 1.23+ and CGO for the default SQLite driver.

```bash
go mod tidy
go test ./...
```

```go
cfg, err := satusehat.ConfigFromEnv()
sdk, err := satusehat.New(cfg)
eventID, err := sdk.EnqueueIdempotent("POST", "Encounter", "", payload, "encounter:local-visit-123:create")
processed, err := sdk.ProcessOnce(context.Background(), 20)
stats, err := sdk.QueueStats()
```
