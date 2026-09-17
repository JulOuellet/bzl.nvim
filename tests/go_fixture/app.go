package app

import (
	"example.test/bzl-external/message"
	"example.test/bzl-sync/generated"
	"example.test/bzl-sync/lib"
)

func Value() string {
	return lib.Value() + generated.Message() + message.Value()
}
