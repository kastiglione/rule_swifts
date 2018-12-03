workspace(name = "rule_swifts")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "build_bazel_rules_swift",
    sha256 = "8fe838514ecfe2f9e7ab4a674f20912d605586320fce57f44bebec8e7f286029",
    strip_prefix = "rules_swift-c38b609153a59b6c7a3b919437e93d01b18c1dbd",
    url = "https://github.com/bazelbuild/rules_swift/archive/c38b609153a59b6c7a3b919437e93d01b18c1dbd.tar.gz",
)

load("@build_bazel_rules_swift//swift:repositories.bzl", "swift_rules_dependencies")
swift_rules_dependencies()
