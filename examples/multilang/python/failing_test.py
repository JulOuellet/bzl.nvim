import unittest


class IntentionalFailureTest(unittest.TestCase):
    def test_failure_output(self) -> None:
        self.fail("Intentional failure: verify bzl.nvim preserves this output.")


if __name__ == "__main__":
    unittest.main()
