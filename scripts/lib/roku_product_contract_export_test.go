package app

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"testing"
)

// This file is overlaid into the canonical app package by the Roku generator.
// It is never copied into or written beneath the server repository.
func TestRokuExportCanonicalProductContract(t *testing.T) {
	payload, err := json.Marshal(canonicalProductContract())
	if err != nil {
		t.Fatalf("marshal canonical Product Contract: %v", err)
	}
	fmt.Printf("PORTICO_ROKU_PRODUCT_CONTRACT:%s\n", base64.StdEncoding.EncodeToString(payload))
}
