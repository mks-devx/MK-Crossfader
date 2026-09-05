#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/mk-privacy-tests.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
git init -q "$work"
mkdir -p "$work/scripts" "$work/macos-app/scripts"
cp "$root/scripts/audit-release.sh" "$work/scripts/"
cp "$root/scripts/privacy-audit.sh" "$work/scripts/"
cp "$root/macos-app/scripts/build-app.sh" "$work/macos-app/scripts/"

expect_clean() {
    zsh "$work/scripts/audit-release.sh" --source-only > "$work/result.log" 2>&1
}
expect_rejected() {
    if zsh "$work/scripts/audit-release.sh" --source-only > "$work/result.log" 2>&1; then
        printf 'Privacy preflight missed %s\n' "$1" >&2
        exit 1
    fi
}

# Keep logs outside Git's source scan while exercising untracked source files.
printf 'result.log\n' > "$work/.gitignore"
expect_clean
printf '/%s/%s/private.txt\n' Users sample-user > "$work/example.txt"
expect_rejected 'untracked home path'
if grep -q 'sample-user' "$work/result.log"; then
    printf 'Privacy preflight exposed the matched value in its output.\n' >&2
    exit 1
fi
git -C "$work" add example.txt
expect_rejected 'tracked home path'
printf '/%s/%s/private.txt\n' Volumes sample-disk > "$work/example.txt"
expect_rejected 'volume path'
printf '%s_%s\n' github_pat '000000000000000000000000000000000000' > "$work/example.txt"
expect_rejected 'synthetic token'
printf '%s@%s\n' example example.invalid > "$work/example.txt"
expect_rejected 'email'
printf '%s\n' 'No private data' > "$work/example.txt"
expect_clean
touch "$work/example.pem"
expect_rejected 'sensitive filename without recognizable contents'
rm "$work/example.pem"
expect_clean
printf '\n# /%s/%s/private.txt\n' Users sample-user >> "$work/scripts/audit-release.sh"
expect_rejected 'private data inside an audit script'
printf 'Privacy preflight regression checks passed.\n'
