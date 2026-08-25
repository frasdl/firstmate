#!/usr/bin/env bash
# Behavior tests for the config/forge knob in bin/fm-bootstrap.sh.
#
# config/forge selects which forge CLI the universal toolchain requires and
# whether the GitHub auth probe fires at session start. github is the default
# and keeps the exact current behavior; gitlab swaps gh/gh-axi for glab and
# never needs GitHub auth; local needs no forge CLI and never raises
# NEEDS_GH_AUTH. An invalid value warns and falls back to github rather than
# silently claiming a typo as fine.
#
# This file is a sibling of fm-bootstrap.test.sh rather than an extension of
# it because the ambient host can carry a real zellij binary that breaks that
# suite's fake-toolchain zellij-absence case; a standalone file keeps the forge
# contract runnable everywhere. The ambient host can equally carry a real gh or
# glab, so every "absent" case runs on a mirrored search path that genuinely
# lacks the tool, never on a bare removal that a real binary on BASE_PATH would
# silently satisfy.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
TMP_ROOT=$(fm_test_tmproot fm-bootstrap-forge-tests)
export FM_BACKEND_CMUX_BUNDLE_BIN="$TMP_ROOT/no-bundled-cmux"

# Hermetic runtime-backend detection, mirroring fm-bootstrap.test.sh: the dev
# shell's ambient runtime markers must not leak into fm_backend_name and flip a
# default-backend case onto a non-tmux backend.
unset TMUX TMUX_PANE HERDR_ENV HERDR_PANE_ID HERDR_SESSION HERDR_SOCKET_PATH \
  CMUX_WORKSPACE_ID CMUX_SURFACE_ID CMUX_SOCKET_PATH CMUX_TAB_ID CMUX_PANEL_ID 2>/dev/null || true

# make_fake_toolchain <case-dir>: a fake toolchain where every required tool is
# present and gh is authenticated. treehouse's `get --help` advertises --lease
# only when FM_FAKE_TREEHOUSE_LEASE_HELP=1.
make_fake_toolchain() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  fm_fake_exit0 "$fakebin" tmux node git chrome-devtools-axi
  fm_fake_version_tool "$fakebin" lavish-axi FM_FAKE_LAVISH_AXI_VERSION 0.1.46
  cat > "$fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  printf '%s\n' "${FM_FAKE_GH_AXI_VERSION:-0.1.29}"
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/gh-axi"
  cat > "$fakebin/gh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/gh"
  cat > "$fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = get ] && [ "${2:-}" = --help ]; then
  if [ "${FM_FAKE_TREEHOUSE_LEASE_HELP:-}" = 1 ]; then
    printf '%s\n' 'Usage: treehouse get [--lease] [--lease-holder <holder>]'
  else
    printf '%s\n' 'Usage: treehouse get'
  fi
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/treehouse"
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then
  printf '%s\n' "${FM_FAKE_NO_MISTAKES_VERSION:-no-mistakes version v1.31.2 (fake) 2026-06-27T00:02:18Z}"
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/no-mistakes"
  cat > "$fakebin/tasks-axi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then printf '%s\n' '0.2.4'; exit 0; fi
if [ "${1:-}" = update ] && [ "${2:-}" = --help ]; then
  printf '%s\n' 'usage: tasks-axi update <id> [flags]'
  printf '%s\n' '  --body-file <path>'
  printf '%s\n' '  --archive-body'
  exit 0
fi
if [ "${1:-}" = mv ] && [ "${2:-}" = --help ]; then
  printf '%s\n' 'usage: tasks-axi mv <id> [<id>...] --to <path-or-dir>'
  exit 0
fi
exit 0
SH
  chmod +x "$fakebin/tasks-axi"
  cat > "$fakebin/quota-axi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then printf '%s\n' '0.1.29'; exit 0; fi
exit 0
SH
  chmod +x "$fakebin/quota-axi"
  printf '%s\n' "$fakebin"
}

# mirror_path_full <dir> <excluded> <bindir>...: re-expose the named bindirs plus
# every directory of BASE_PATH by symlink into <dir>, with every <excluded> tool
# omitted so a real host binary cannot leak in through BASE_PATH and decide a
# "required" or "absent" verdict. Excluded is a whitespace-separated set.
mirror_path_full() {
  local dir=$1 excluded=$2 search bindir entry name
  shift 2
  mkdir -p "$dir"
  search=$(printf '%s\n' "$@"; printf '%s\n' "$BASE_PATH" | tr ':' '\n')
  while IFS= read -r bindir; do
    [ -d "$bindir" ] || continue
    for entry in "$bindir"/*; do
      [ -e "$entry" ] || continue
      name=${entry##*/}
      case " $excluded " in *" $name "*) continue ;; esac
      [ -e "$dir/$name" ] || ln -s "$entry" "$dir/$name" 2>/dev/null
    done
  done <<EOF
$search
EOF
  for name in $excluded; do
    ! PATH="$dir" command -v "$name" >/dev/null 2>&1 \
      || fail "the $name-free search path still resolved $name"
  done
  [ -d "$dir" ] || return 1
}

# Fake glab stub for a gitlab case, dropped into the fakebin before mirroring so
# the only glab the mirror can ever contain is this stub.
add_fake_glab() {  # <fakebin>
  local fakebin=$1
  cat > "$fakebin/glab" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$fakebin/glab"
}

# Forge github default: gh and gh-axi are required, glab is not, and a failing
# gh auth status fires the NEEDS_GH_AUTH probe.
test_forge_github_default_requires_gh_and_axi_and_auth() {
  local case_dir fakebin out
  case_dir="$TMP_ROOT/forge-github-default"
  mkdir -p "$case_dir/home"
  fakebin=$(make_fake_toolchain "$case_dir")
  # Default (no config/forge) keeps the github toolchain. Remove gh and gh-axi
  # from the FAKEBIN before mirroring, so the mirror provably lacks them and a
  # real host binary can never satisfy the requirement.
  rm -f "$fakebin/gh" "$fakebin/gh-axi"
  mirror_path_full "$case_dir/mirror" "gh gh-axi" "$fakebin"
  out=$(PATH="$case_dir/mirror" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh")
  assert_contains "$out" "MISSING: gh (install: brew install gh" \
    "forge-github-default: gh was not required on the default github forge"
  assert_contains "$out" "MISSING: gh-axi (install: npm install -g gh-axi" \
    "forge-github-default: gh-axi was not required on the default github forge"
  assert_not_contains "$out" "MISSING: glab" \
    "forge-github-default: glab was required on a github home"

  # With gh present but unauthenticated, the GitHub auth probe must fire. The
  # failing gh goes into the fakebin BEFORE mirroring so the mirror's gh is the
  # fake, never a real host binary.
  fakebin=$(make_fake_toolchain "$case_dir")
  cat > "$fakebin/gh" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = auth ] && [ "${2:-}" = status ]; then exit 1; fi
exit 0
SH
  chmod +x "$fakebin/gh"
  mirror_path_full "$case_dir/mirror-auth" "" "$fakebin"
  out=$(PATH="$case_dir/mirror-auth" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh")
  assert_contains "$out" "NEEDS_GH_AUTH" "forge-github-default: the GitHub auth probe did not fire on github"
  pass "bootstrap forge: github default requires gh and gh-axi and probes GitHub auth"
}

test_forge_gitlab_requires_glab_not_gh_and_no_auth() {
  local case_dir fakebin out
  case_dir="$TMP_ROOT/forge-gitlab"
  mkdir -p "$case_dir/home/config"
  printf '%s\n' gitlab > "$case_dir/home/config/forge"
  # A gitlab home needs glab, never gh/gh-axi. The fake glab goes into the
  # fakebin BEFORE mirroring so a real host glab cannot decide the verdict.
  fakebin=$(make_fake_toolchain "$case_dir")
  rm -f "$fakebin/gh" "$fakebin/gh-axi"
  add_fake_glab "$fakebin"
  mirror_path_full "$case_dir/mirror" "gh gh-axi" "$fakebin"
  out=$(PATH="$case_dir/mirror" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh")
  assert_not_contains "$out" "MISSING: gh" "forge-gitlab: gh was required on a gitlab home"
  assert_not_contains "$out" "MISSING: gh-axi" "forge-gitlab: gh-axi was required on a gitlab home"
  assert_not_contains "$out" "NEEDS_GH_AUTH" "forge-gitlab: a gitlab home probed GitHub auth"
  assert_not_contains "$out" "MISSING: glab" "forge-gitlab: a present glab was reported missing"

  # With glab genuinely absent, a gitlab home reports it missing, with a usable
  # install instruction, and still never probes GitHub auth.
  rm -f "$fakebin/glab"
  mirror_path_full "$case_dir/mirror-no-glab" "gh gh-axi glab" "$fakebin"
  out=$(PATH="$case_dir/mirror-no-glab" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh")
  assert_contains "$out" "MISSING: glab (install: brew install glab" \
    "forge-gitlab: absent glab was not reported with an install instruction"
  assert_not_contains "$out" "NEEDS_GH_AUTH" "forge-gitlab: a gitlab home probed GitHub auth when glab was absent"
  pass "bootstrap forge: gitlab requires glab, never gh/gh-axi, and never probes GitHub auth"
}

test_forge_local_requires_no_forge_cli_and_no_auth() {
  local case_dir fakebin out
  case_dir="$TMP_ROOT/forge-local"
  mkdir -p "$case_dir/home/config"
  printf '%s\n' local > "$case_dir/home/config/forge"
  fakebin=$(make_fake_toolchain "$case_dir")
  rm -f "$fakebin/gh" "$fakebin/gh-axi" "$fakebin/no-mistakes"
  # A local home must pass silently with no forge CLI and no no-mistakes on the
  # search path, because local work lands through the guarded fast-forward path.
  mirror_path_full "$case_dir/mirror" "gh gh-axi glab no-mistakes" "$fakebin"
  out=$(PATH="$case_dir/mirror" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh")
  assert_not_contains "$out" "MISSING: gh" "forge-local: gh was required on a local home"
  assert_not_contains "$out" "MISSING: gh-axi" "forge-local: gh-axi was required on a local home"
  assert_not_contains "$out" "MISSING: glab" "forge-local: glab was required on a local home"
  assert_not_contains "$out" "MISSING: no-mistakes" "forge-local: no-mistakes was required on a local home"
  assert_not_contains "$out" "NEEDS_GH_AUTH" "forge-local: a local home probed GitHub auth"
  pass "bootstrap forge: local requires no forge CLI, no no-mistakes, and never probes GitHub auth"
}

test_forge_gitlab_requires_no_mistakes() {
  local case_dir fakebin out
  case_dir="$TMP_ROOT/forge-gitlab-no-mistakes"
  mkdir -p "$case_dir/home/config"
  printf '%s\n' gitlab > "$case_dir/home/config/forge"
  fakebin=$(make_fake_toolchain "$case_dir")
  rm -f "$fakebin/gh" "$fakebin/gh-axi" "$fakebin/no-mistakes"
  add_fake_glab "$fakebin"
  # A gitlab home keeps no-mistakes (a forge-backed validation tool), so an
  # absent no-mistakes is reported even when gh/gh-axi are not required.
  mirror_path_full "$case_dir/mirror" "gh gh-axi no-mistakes" "$fakebin"
  out=$(PATH="$case_dir/mirror" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh")
  assert_not_contains "$out" "MISSING: gh" "forge-gitlab-no-mistakes: gh was required on a gitlab home"
  assert_contains "$out" "MISSING: no-mistakes (install: curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh)" \
    "forge-gitlab-no-mistakes: absent no-mistakes was not reported on a gitlab home"
  assert_not_contains "$out" "NEEDS_GH_AUTH" "forge-gitlab-no-mistakes: a gitlab home probed GitHub auth"
  pass "bootstrap forge: gitlab requires no-mistakes, local omits it"
}

test_forge_invalid_value_defaults_to_github_with_warning() {
  local case_dir fakebin out err
  case_dir="$TMP_ROOT/forge-invalid"
  mkdir -p "$case_dir/home/config"
  printf '%s\n' bitbucket > "$case_dir/home/config/forge"
  fakebin=$(make_fake_toolchain "$case_dir")
  # An invalid value must warn and fall back to the github toolchain, so gh and
  # gh-axi become required and a path without them reports both.
  rm -f "$fakebin/gh" "$fakebin/gh-axi"
  mirror_path_full "$case_dir/mirror" "gh gh-axi" "$fakebin"
  out=$(PATH="$case_dir/mirror" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh")
  assert_contains "$out" "MISSING: gh (install: brew install gh" \
    "forge-invalid: an invalid forge did not fall back to the github toolchain"
  err=$(PATH="$case_dir/mirror" FM_HOME="$case_dir/home" FM_ROOT_OVERRIDE="$case_dir/home" \
    FM_FAKE_TREEHOUSE_LEASE_HELP=1 "$ROOT/bin/fm-bootstrap.sh" 2>&1 >/dev/null)
  assert_contains "$err" "BOOTSTRAP_INFO: config/forge 'bitbucket' is not a known forge" \
    "forge-invalid: an invalid forge did not warn it was ignored"
  pass "bootstrap forge: an invalid config/forge warns and defaults to github, never silently"
}

test_forge_github_default_requires_gh_and_axi_and_auth
test_forge_gitlab_requires_glab_not_gh_and_no_auth
test_forge_gitlab_requires_no_mistakes
test_forge_local_requires_no_forge_cli_and_no_auth
test_forge_invalid_value_defaults_to_github_with_warning