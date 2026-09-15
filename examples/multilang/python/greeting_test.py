import unittest

from acme.greeting import greet


class GreetingTest(unittest.TestCase):
    def test_greeting(self) -> None:
        self.assertEqual(greet("Bazel"), "Hello, Bazel! (v1.2.0)")


if __name__ == "__main__":
    unittest.main()
