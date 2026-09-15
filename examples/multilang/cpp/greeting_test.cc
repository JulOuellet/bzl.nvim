#include <iostream>
#include "multilang/greeting.h"

int main() {
    if (greet("Bazel") != "Hello, Bazel!") {
        std::cerr << "Unexpected greeting\n";
        return 1;
    }
    return 0;
}
