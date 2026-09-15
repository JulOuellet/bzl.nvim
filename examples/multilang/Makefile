.PHONY: query build test run failing-test

query:
	bazel query //... --output=label_kind

build:
	bazel build //...

test:
	bazel test //...

run:
	bazel run //python:app
	bazel run //python:generated_app
	bazel run //cpp:app
	bazel run //go:app
	bazel run //rust:app
	bazel run //java:app

# This command intentionally exits nonzero.
failing-test:
	bazel test //python:failing_test
