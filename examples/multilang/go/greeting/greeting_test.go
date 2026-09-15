package greeting

import "testing"

func TestGreet(t *testing.T) {
	if got := Greet("Bazel"); got != "Hello, Bazel!" {
		t.Fatalf("unexpected greeting: %q", got)
	}
}
