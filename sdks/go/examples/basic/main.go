package main

import (
	"context"
	"fmt"
	satusehat "github.com/satusehat-platform/integration-sdk/sdks/go"
	"log"
)

func main() {
	cfg, err := satusehat.ConfigFromEnv()
	if err != nil {
		log.Fatal(err)
	}
	sdk, err := satusehat.New(cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer sdk.Close()
	id, err := sdk.Enqueue("POST", "Encounter", "", []byte(`{"resourceType":"Encounter","status":"finished"}`))
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("queued", id)
	n, err := sdk.ProcessOnce(context.Background(), 20)
	fmt.Println("processed", n, "error", err)
}
