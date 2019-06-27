#!/bin/bash

# Runs a single srb init test from gems/sorbet/test/snapshot/{partial,total}/*

shopt -s dotglob

# --- begin runfiles.bash initialization ---
# Copy-pasted from Bazel's Bash runfiles library https://github.com/bazelbuild/bazel/blob/defd737761be2b154908646121de47c30434ed51/tools/bash/runfiles/runfiles.bash
set -euo pipefail
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  # shellcheck disable=SC1090
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  # shellcheck disable=SC1090
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---

# ----- Option parsing -----

# these positional arguments are supplied in snapshot.bzl
ruby_package=$1
test_name=$2

if [[ "${test_name}" =~ partial/* ]]; then
  is_partial=1
else
  is_partial=
fi

echo "test_name:  ${test_name}"
echo "is_partial: ${is_partial:-0}"

# ----- Environment setup -----

# Add ruby to the path
PATH="$(dirname "$(rlocation "${ruby_package}/ruby")"):$PATH"

# Put the bundler library into RUBYLIB
source $(rlocation "gems/bundler/bundle-env")

# Add bundler to the path
BUNDLER_LOC=$(dirname "$(rlocation "gems/bundler/bundle")")
GEMS_LOC="$BUNDLER_LOC/../gems"
PATH="$BUNDLER_LOC:$PATH"

export PATH

repo_root="$PWD"

source "gems/sorbet/test/snapshot/logging.sh"

test_dir="${repo_root}/gems/sorbet/test/snapshot/$2"

actual="${test_dir}/actual"

srb="${repo_root}/gems/sorbet/bin/srb"

# Use the sorbet executable built by bazel
SRB_SORBET_EXE="$PWD/main/sorbet"

HOME=$test_dir
export HOME


# ----- Build the test sandbox -----

cp -r "${test_dir}/src" "$actual"


# ----- Run the test -----

(
  cd $actual

  # Setup the vendor/cache directory to include all gems required for any test
  mkdir vendor
  ln -s "$GEMS_LOC" "vendor/cache"

  # https://bundler.io/v2.0/man/bundle-install.1.html#DEPLOYMENT-MODE
  # Passing --local to never consult rubygems.org
  bundle install --deployment --local

  bundle check

  # Uses /dev/null for stdin so any binding.pry would exit immediately
  # (otherwise, pry will be waiting for input, but it's impossible to tell
  # because the pry output is hiding in the *.log files)
  #
  # note: redirects stderr before the pipe
  if ! SRB_YES=1 bundle exec "$srb" init < /dev/null 2> "err.log" > "out.log"; then
    error "├─ srb init failed."
    error "├─ stdout (out.log):"
    cat "out.log"
    error "├─ stderr (err.log):"
    cat "err.log"
    error "└─ (end stderr)"
    exit 1
  fi

)

(
  cd $test_dir

  # ----- Check out.log -----

  info "Checking output log"
  if [ "$is_partial" = "" ] || [ -f "expected/out.log" ]; then
    out_filtered="$(mktemp)"
    sed -e 's/with [0-9]* modules and [0-9]* aliases/with X modules and Y aliases/' \
      < "actual/out.log" \
      | sed -e "s,${TMPDIR}[^ ]*/\([^/]*\),<tmp>/\1,g" \
      > "$out_filtered"
    mv "$out_filtered" "actual/out.log"
    if ! diff -u "expected/out.log" "actual/out.log"; then
      error "├─ expected out.log did not match actual out.log"
      error "└─ see output above."
      exit 1
    fi
  fi

  # ----- Check err.log -----

  if [ "$is_partial" = "" ] || [ -f "expected/err.log" ]; then
    if ! diff -u "expected/err.log" "actual/err.log"; then
      error "├─ expected err.log did not match actual err.log"
      error "└─ see output above."
      exit 1
    fi
  fi

  # ----- Check sorbet/ -----

  # FIXME: Removing hidden-definitions in actual to hide them from diff output.
  rm -rf "$actual/src/sorbet/rbi/hidden-definitions"

  diff_total() {
    if ! diff -ur "$test_dir/expected/sorbet" "$actual/src/sorbet"; then
      error "├─ expected sorbet/ folder did not match actual sorbet/ folder"
      error "└─ see output above. Run with --update to fix."
      exit 1
    fi
  }

  diff_partial() {
    set +e
    diff -ur "$test_dir/expected/sorbet" "$actual/src/sorbet" | \
      grep -vF "Only in $actual" \
      > "$actual/src/partial-diff.log"
    set -e

    # File exists and is non-empty
    if [ -s "$actual/src/partial-diff.log" ]; then
      cat "$actual/src/partial-diff.log"
      error "├─ expected sorbet/ folder did not match actual sorbet/ folder"
      error "└─ see output above."
      exit 1
    fi
  }

  if [ "$is_partial" = "" ]; then
    diff_total
  elif [ -d "$test_dir/expected/sorbet" ]; then
    diff_partial
  else
    # It's fine for a partial test to not have an expected dir.
    # It means the test only cares about the exit code of srb init.
    true
  fi

  success "└─ test passed."
)
