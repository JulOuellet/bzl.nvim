pub fn greet(name: &str) -> String {
    format!("Hello, {name}!")
}

#[cfg(test)]
mod tests {
    use super::greet;

    #[test]
    fn greeting_matches() {
        assert_eq!(greet("Bazel"), "Hello, Bazel!");
    }
}
