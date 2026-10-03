#!/bin/sh
# gh-runs — recent GitHub Actions runs across your most recently pushed repos.
# Output: TSV newest-first: repo, created_at, status, conclusion, workflow, title, branch, url
# Tabs inside titles are blanked so QML can split on \t safely.
# Per-repo fetches run in parallel into separate files (no interleaving);
# first API page only — [:8] never needs --paginate (that walked every page).
# NOTE: the repo list is spooled to a file first so the loop runs in the
# main shell — inside a pipeline the loop is a subshell and `wait` would
# return before the background jobs finish.
OUT=$(mktemp -d) || exit 1
trap 'rm -rf "$OUT"' EXIT INT TERM
gh repo list --limit 8 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null > "$OUT/repos.txt"
while IFS= read -r r; do
    [ -z "$r" ] && continue
    safe=$(printf '%s' "$r" | tr '/.' '__')
    {
        gh api "repos/$r/actions/runs" \
            -q '.workflow_runs[:8][] | [.created_at, .status, (.conclusion // ""), (.name | gsub("\t";" ")), (.display_title | gsub("\t";" ")), .head_branch, .html_url] | @tsv' \
            2>/dev/null | while IFS= read -r line; do
            [ -z "$line" ] && continue
            printf '%s\t%s\n' "$r" "$line"
        done > "$OUT/$safe.tsv"
    } &
done < "$OUT/repos.txt"
wait
cat "$OUT"/*.tsv 2>/dev/null | sort -t '	' -k2,2r | head -n 20
