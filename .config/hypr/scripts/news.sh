#!/bin/bash

API_KEY="YOUR_NEWSAPI_KEY_HERE"  # Get a free key at https://newsapi.org
CACHE_FILE="/tmp/hyperlock_news.txt"
INDEX_FILE="/tmp/hyperlock_news_index.txt"
SEEN_FILE="/tmp/hyperlock_news_seen.txt"
CACHE_TIME=300

fetch() {
    local url=$1
    curl -s "$url"
}

generate_feed() {
    > "$CACHE_FILE"

    # nigeria - query based since country=ng unreliable on free tier
    fetch "https://newsapi.org/v2/everything?\
q=nigeria&\
sortBy=publishedAt&\
pageSize=8&\
language=en&\
apiKey=${API_KEY}" | jq -r '.articles[]? | .title' >> "$CACHE_FILE"

    # us general
    fetch "https://newsapi.org/v2/top-headlines?\
country=us&\
category=general&\
pageSize=8&\
apiKey=${API_KEY}" | jq -r '.articles[]? | .title' >> "$CACHE_FILE"

    # tech - more results
    fetch "https://newsapi.org/v2/top-headlines?\
country=us&\
category=technology&\
pageSize=10&\
apiKey=${API_KEY}" | jq -r '.articles[]? | .title' >> "$CACHE_FILE"

    # more tech from sources
    fetch "https://newsapi.org/v2/top-headlines?\
sources=techcrunch,the-verge,wired,ars-technica&\
pageSize=10&\
apiKey=${API_KEY}" | jq -r '.articles[]? | .title' >> "$CACHE_FILE"

    # world
    fetch "https://newsapi.org/v2/top-headlines?\
sources=bbc-news,reuters,associated-press&\
pageSize=8&\
apiKey=${API_KEY}" | jq -r '.articles[]? | .title' >> "$CACHE_FILE"

    # clean empty lines and truncate long titles
    sed -i '/^$/d' "$CACHE_FILE"
    sed -i 's/.\{80\}/&\n/g' "$CACHE_FILE"
}

check_and_notify() {
    touch "$SEEN_FILE"

    # fetch latest tech news
    local latest
    latest=$(fetch "https://newsapi.org/v2/top-headlines?\
sources=techcrunch,the-verge,wired&\
pageSize=5&\
apiKey=${API_KEY}")

    echo "$latest" | jq -c '.articles[]?' | while read -r article; do
        local title
        local url
        local image
        title=$(echo "$article" | jq -r '.title')
        url=$(echo "$article" | jq -r '.url')
        image=$(echo "$article" | jq -r '.urlToImage')

        # check if already seen
        if ! grep -qF "$title" "$SEEN_FILE"; then
            echo "$title" >> "$SEEN_FILE"

            # send notification with image if exists
            if [ "$image" != "null" ] && [ -n "$image" ]; then
                local img_path="/tmp/news_notify.jpg"
                curl -s -o "$img_path" "$image"
                notify-send \
                    -i "$img_path" \
                    -u normal \
                    -t 8000 \
                    "tech news" "$title"
            else
                notify-send \
                    -u normal \
                    -t 8000 \
                    "tech news" "$title"
            fi
        fi
    done

    # keep seen file from growing forever
    tail -100 "$SEEN_FILE" > "${SEEN_FILE}.tmp" && mv "${SEEN_FILE}.tmp" "$SEEN_FILE"
}

get_current_headline() {
    local total
    total=$(wc -l < "$CACHE_FILE")
    [ "$total" -eq 0 ] && echo "no news available" && echo "updated: $(date '+%H:%M')" && return

    local index=0
    if [ -f "$INDEX_FILE" ]; then
        index=$(cat "$INDEX_FILE")
    fi

    local headline
    headline=$(sed -n "$((index + 1))p" "$CACHE_FILE")

    local next=$(( (index + 1) % total ))
    echo "$next" > "$INDEX_FILE"

    echo "$headline"
    echo "updated: $(date '+%H:%M')"
}

# refresh cache if stale
if [ ! -f "$CACHE_FILE" ] || [ $(( $(date +%s) - $(date +%s -r "$CACHE_FILE") )) -gt $CACHE_TIME ]; then
    generate_feed
    check_and_notify
fi

get_current_headline