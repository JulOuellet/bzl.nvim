import unittest

from build_info import BUILD_MESSAGE


class GeneratedTest(unittest.TestCase):
    def test_generated_import(self) -> None:
        self.assertEqual(BUILD_MESSAGE, "Hello from generated Python!")


if __name__ == "__main__":
    unittest.main()
