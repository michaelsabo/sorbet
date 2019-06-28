load(":snapshot.bzl", _snapshot_test = "snapshot_test", _snapshot_tests = "snapshot_tests")

sh_library(
    name = "logging",
    srcs = ["logging.sh"],
)

test_suite(
    name = "snapshot",
    tests =
        _snapshot_tests(glob([
            "partial/*",
            "total/*",
        ], exclude = [
            # TIMEOUT
            "partial/stupidedi",
            "partial/rbi_list",

            # openssl
            "partial/webmock",
            "partial/partially-sigged",

            # native extensions
            "partial/codecov",
            "partial/rails-double-require",
        ],

        # We only want to match directories with this glob
        exclude_directories = 0,
    )),
)
