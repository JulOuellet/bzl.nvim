package demo;

public final class Greeting {
    private Greeting() {}

    public static String greet(String name) {
        return "Hello, " + name + "!";
    }
}
