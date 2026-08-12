# Go SDK

Requires Go 1.23+ and CGO for the default SQLite driver.

```bash
go mod tidy
go test ./...
```

```go
cfg, err := satusehat.ConfigFromEnv()
sdk, err := satusehat.New(cfg)
eventID, err := sdk.Enqueue("POST", "Encounter", "", payload)
processed, err := sdk.ProcessOnce(context.Background(), 20)
```
