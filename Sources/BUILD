# load("@rule_swifts//rules:pipelined.bzl", "swift_library")
load("@rule_swifts//rules:incremental.bzl", "swift_library")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_binary")

swift_library(
  name = "A",
  srcs = glob(["A/*.swift"]),
)

swift_library(
  name = "B",
  srcs = glob(["B/*.swift"]),
  deps = [":A"],
)

swift_library(
  name = "C",
  srcs = glob(["C/*.swift"]),
  deps = [":B"],
)

swift_binary(
  name = "runme",
  module_name = "runme",
  srcs = ["main.swift"],
  deps = [":C"],
)
