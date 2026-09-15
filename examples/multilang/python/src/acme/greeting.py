from packaging.version import Version


def greet(name: str) -> str:
    version = Version("1.2.0")
    return f"Hello, {name}! (v{version})"
