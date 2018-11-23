load("@rule_swifts//rules:twophase.bzl", "swift_library")
# load("@rule_swifts//rules:incremental.bzl", "swift_library")

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
