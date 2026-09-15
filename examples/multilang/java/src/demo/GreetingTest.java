package demo;

public final class GreetingTest {
    public static void main(String[] args) {
        if (!Greeting.greet("Bazel").equals("Hello, Bazel!")) {
            throw new AssertionError("Unexpected greeting");
        }
    }
}
