package app

import "testing"

func TestValue(t *testing.T) {
	if Value() == "" {
		t.Fatal("empty value")
	}
}
