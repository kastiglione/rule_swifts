workspace(name = "rule_swifts")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "build_bazel_rules_swift",
    sha256 = "b87d5d6c3672fc8f0e462812dda69c2ab3ab3e506c8a299d91357f8749ab0017",
    strip_prefix = "rules_swift-08f67a8141d7d15a57bbfadd58873303a8c7da34",
    url = "https://github.com/bazelbuild/rules_swift/archive/08f67a8141d7d15a57bbfadd58873303a8c7da34.tar.gz",
)

load("@build_bazel_rules_swift//swift:repositories.bzl", "swift_rules_dependencies")
swift_rules_dependencies()
