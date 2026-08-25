#!/usr/bin/env bash
# fm-forge-lib.sh - single owner of the config/forge contract.
#
# The local, gitignored config/forge file selects which forge a home targets.
# It accepts one word on its first non-empty line: github (default), gitlab, or
# local. An unrecognized word is reported as an actionable BOOTSTRAP_INFO line
# to stderr and falls back to github, never silently claiming a typo as fine.
#
# forge name                    forge CLI required   GitHub auth probe
# github (default)              gh + gh-axi          yes
# gitlab                        glab                 no
# local                         none                 no
#
# Consumers: bin/fm-bootstrap.sh (universal toolchain selection and the auth
# probe) and bin/fm-startup-network.sh (digest phase labels). This file is
# sourced, never executed.
set -u

FM_FORGE_CONFIG_DIR="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
FM_FORGE_KNOWN="github gitlab local"

fm_forge_name() {  # resolves config/forge (github|gitlab|local), defaulting to github
  local line v
  if [ -f "$FM_FORGE_CONFIG_DIR/forge" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      v=$(printf '%s' "$line" | tr -d '[:space:]')
      if [ -n "$v" ]; then
        case " $FM_FORGE_KNOWN " in
          *" $v "*) printf '%s' "$v" ; return 0 ;;
          *) echo "BOOTSTRAP_INFO: config/forge '$v' is not a known forge (known: $FM_FORGE_KNOWN); defaulting to github" >&2 ;;
        esac
      fi
    done < "$FM_FORGE_CONFIG_DIR/forge"
  fi
  printf 'github'
}

fm_forge_is_github() {  # true when the resolved forge needs the GitHub auth probe
  [ "$(fm_forge_name)" = github ]
}