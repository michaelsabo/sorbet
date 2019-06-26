load(":snapshot.bzl", _snapshot_test = "snapshot_test", _snapshot_tests = "snapshot_tests")

sh_library(
    name = "logging",
    srcs = ["logging.sh"],
)

test_suite(
    name = "snapshot",
    tests = [
        _snapshot_test("partial/typed-ignore"),
        _snapshot_test("partial/require_relative"),

        # fails due to cloning message in err.log
        # _snapshot_test("total/empty"),
    ],
)
