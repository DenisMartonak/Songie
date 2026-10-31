#!/usr/bin/env bash
# Scan the whole git history and the current tree for secrets before the
# repository is made public. REPORT ONLY: nothing is ever rewritten or fixed.
#
# Usage: tool/scan_secrets.sh      (run from anywhere inside the repo)
# Exit:  0 clean, 1 hits found.
#
# Never prints a full secret: a content hit shows the first 4 characters
# followed by an ellipsis.
#
# Portability: bash + GNU grep (uses `grep -P`) + awk. Fine on Linux; on macOS
# install GNU grep (ggrep) and alias it.
#
# Notes on the patterns (they are written so this file does not match itself):
#  - `[-]----BEGIN` is the same as five dashes; it only avoids a self-hit.
#  - ghp_ / github_pat_ need 20+ token characters after the prefix, so the bare
#    word "ghp_" in prose does not match.
#  - password matches whose value starts with `<` (a doc placeholder), starts
#    with `$` (a variable or CI expression) or is "your-password" /
#    "your_password" are counted and skipped. The skipped count is printed.
#  - Filenames under test/ are listed separately and do not fail the scan.
#    Content hits under test/ still count and are labelled "[test fixture]".
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
hits="$work/hits"       # content hits that fail the scan
name_hits="$work/names" # filename hits outside test/
test_names="$work/tnames"
: >"$hits"
: >"$name_hits"
: >"$test_names"
skipped=0

# name<TAB>regex (PCRE)
patterns=(
  $'private-key\t[-]----BEGIN .*PRIVATE KEY-----'
  $'github-token\tghp_[A-Za-z0-9]{20,}'
  $'github-pat\tgithub_pat_[A-Za-z0-9_]{20,}'
  $'aws-access-key\tAKIA[0-9A-Z]{16}'
  $'google-cookie\t(SAPISID|__Secure-3PSID)\\s*=\\s*[A-Za-z0-9._/%+-]{20,}'
  $'password\tpassword\\s*[:=]\\s*\\S{6,}'
)

redact() { printf '%s…' "${1:0:4}"; }

# Lines of "label<TAB>path<TAB>content" for every ADDED line in all history.
# Only added lines matter: anything ever removed was added in an earlier commit.
git log -p --all --no-color --no-ext-diff --format='commit %h' |
  awk '
    /^commit [0-9a-f]+$/ { sha=$2; inhdr=0; next }
    /^diff --git/        { inhdr=1; next }
    inhdr && /^\+\+\+ /  { p=substr($0,5); sub(/^b\//,"",p); path=p; next }
    /^@@/                { inhdr=0; next }
    !inhdr && /^\+/      { printf "%s\t%s\t%s\n", sha, path, substr($0,2) }
  ' >"$work/history.tsv"

# Same shape for the working tree (tracked + untracked, not ignored).
git ls-files -co --exclude-standard -z |
  xargs -0 grep -IHs '' |
  sed 's/^\([^:]*\):/working tree\t\1\t/' >"$work/tree.tsv" || true

scan_tsv() { # file
  local file="$1" entry name re line label rest path content m
  for entry in "${patterns[@]}"; do
    name="${entry%%$'\t'*}"
    re="${entry#*$'\t'}"
    while IFS= read -r line; do
      label="${line%%$'\t'*}"
      rest="${line#*$'\t'}"
      path="${rest%%$'\t'*}"
      content="${rest#*$'\t'}"
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        if [ "$name" = password ]; then
          local val="${m#*[:=]}"
          val="${val#"${val%%[![:space:]]*}"}"
          case "$val" in
            '<'* | '$'* | your-password* | your_password*)
              skipped=$((skipped + 1))
              continue
              ;;
          esac
        fi
        local tag=""
        case "$path" in test/*) tag=" [test fixture]" ;; esac
        printf '%s\t%s\t%s\t%s%s\n' "$label" "$path" "$name" "$(redact "$m")" "$tag" >>"$hits"
      done < <(printf '%s\n' "$content" | grep -oP -- "$re" || true)
    done < <(grep -P -- "^[^\t]*\t[^\t]*\t.*(?:$re)" "$file" || true)
  done
}

scan_tsv "$work/history.tsv"
scan_tsv "$work/tree.tsv"

# Filenames: every path ever touched in any commit, plus the working tree.
name_re='(^|/)(key\.properties|\.env[^/]*|[^/]*\.(jks|keystore|pem))$'
{
  git log --all --name-only --no-color --format='commit %h' |
    awk '/^commit [0-9a-f]+$/ { sha=$2; next } NF { print sha "\t" $0 }'
  git ls-files -co --exclude-standard | awk '{ print "working tree\t" $0 }'
} | { grep -P -- "^[^\t]*\t.*$name_re" || true; } |
  awk -F'\t' '{ n[$2]++; if (!($2 in first)) first[$2]=$1; last[$2]=$1 }
              END { for (p in n) printf "%s\t%s\t%d\n", last[p], p, n[p] }' |
  sort -t$'\t' -k2 |
  while IFS=$'\t' read -r sha path count; do
    case "$path" in
      test/*) printf '%s\t%s\t%s\n' "$sha" "$path" "$count" >>"$test_names" ;;
      *) printf '%s\t%s\t%s\n' "$sha" "$path" "$count" >>"$name_hits" ;;
    esac
  done

status=0

echo "== Sensitive file names (oldest commit touching the path, or working tree) =="
if [ -s "$name_hits" ]; then
  while IFS=$'\t' read -r sha path count; do
    printf '  %s  %s  (in %s listing(s))\n' "$sha" "$path" "$count"
  done <"$name_hits"
  status=1
else
  echo "  none"
fi

echo
echo "== Sensitive file names under test/ (fixtures, informational) =="
if [ -s "$test_names" ]; then
  while IFS=$'\t' read -r sha path count; do
    printf '  %s  %s\n' "$sha" "$path"
  done <"$test_names"
else
  echo "  none"
fi

echo
echo "== Content hits (value redacted to first 4 characters) =="
if [ -s "$hits" ]; then
  sort -u "$hits" | while IFS=$'\t' read -r label path name red; do
    printf '  %s  %s  [%s]  %s\n' "$label" "$path" "$name" "$red"
  done
  status=1
else
  echo "  none"
fi
echo "  (skipped $skipped password match(es) with <placeholder>, \$VAR or your-password values)"

if command -v gitleaks >/dev/null 2>&1; then
  echo
  echo "== gitleaks =="
  if ! gitleaks detect --log-opts=--all --redact; then
    status=1
  fi
else
  echo
  echo "gitleaks not on PATH; skipped."
fi

echo
if [ "$status" -eq 0 ]; then
  echo "CLEAN: no secrets found."
else
  echo "HITS FOUND: review above. Nothing was changed."
fi
exit "$status"
