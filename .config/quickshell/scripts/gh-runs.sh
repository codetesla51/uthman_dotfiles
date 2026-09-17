#!/bin/sh
# gh-runs — recent GitHub Actions runs across your most recently pushed repos.
# Output: TSV newest-first: repo, created_at, status, conclusion, workflow, title, branch, url
# Tabs inside titles are blanked so QML can split on \t safely.
gh repo list --limit 8 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null | while IFS= read -r r; do
    [ -z "$r" ] && continue
    gh api "repos/$r/actions/runs" --paginate \
        -q '.workflow_runs[:8][] | [.created_at, .status, (.conclusion // ""), (.name | gsub("\t";" ")), (.display_title | gsub("\t";" ")), .head_branch, .html_url] | @tsv' \
        2>/dev/null | while IFS= read -r line; do
        [ -z "$line" ] && continue
        printf '%s\t%s\n' "$r" "$line"
    done
done | sort -t '	' -k2,2r | head -n 20
