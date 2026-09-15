from acme.greeting import greet

# This file is intentionally outside all Bazel targets.
# Once imports resolve, a functioning type checker should still flag this call.
greet(123)
