#!/usr/bin/env bash
# darkweb-search.sh - Helper script for dark web OSINT searches via Tor
#
# Usage:
#   darkweb-search.sh check-tor       - Verify Tor is running
#   darkweb-search.sh start-tor       - Start Tor and wait for bootstrap
#   darkweb-search.sh extract-onions  - Extract .onion URLs from stdin
#   darkweb-search.sh fetch <url>     - Fetch a URL through Tor
#   darkweb-search.sh search <query>  - Search Ahmia for .onion results
#   darkweb-search.sh crawl <url> [depth] - Crawl an .onion site for links

set -euo pipefail

TOR_PROXY="127.0.0.1:9050"
CURL_TIMEOUT=30
REQUEST_DELAY=2

check_tor() {
    if ! pgrep -x tor > /dev/null 2>&1; then
        echo "ERROR: Tor is not running"
        return 1
    fi

    local status
    status=$(curl --socks5-hostname "$TOR_PROXY" \
        -s -o /dev/null -w "%{http_code}" \
        --max-time 15 \
        "https://check.torproject.org" 2>/dev/null || echo "000")

    if [ "$status" = "200" ]; then
        echo "OK: Tor SOCKS proxy is reachable and functional"
        return 0
    else
        echo "ERROR: Tor is running but SOCKS proxy returned HTTP $status"
        return 1
    fi
}

start_tor() {
    if pgrep -x tor > /dev/null 2>&1; then
        echo "Tor is already running"
        check_tor
        return $?
    fi

    echo "Starting Tor..."
    tor &
    local tor_pid=$!

    # Wait for Tor to bootstrap (up to 60 seconds)
    local waited=0
    while [ $waited -lt 60 ]; do
        if curl --socks5-hostname "$TOR_PROXY" \
            -s -o /dev/null \
            --max-time 5 \
            "https://check.torproject.org" 2>/dev/null; then
            echo "OK: Tor started and bootstrapped successfully (PID: $tor_pid)"
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
        echo "Waiting for Tor to bootstrap... (${waited}s)"
    done

    echo "ERROR: Tor failed to bootstrap within 60 seconds"
    return 1
}

extract_onions() {
    # Extract unique .onion addresses from stdin
    # Matches both v2 (16 char) and v3 (56 char) onion addresses
    grep -oiE '[a-z2-7]{16,56}\.onion' | sort -u
}

fetch_url() {
    local url="$1"
    curl --socks5-hostname "$TOR_PROXY" \
        -s -L \
        --max-time "$CURL_TIMEOUT" \
        --retry 2 \
        --retry-delay 3 \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0" \
        "$url" 2>/dev/null
}

fetch_with_metadata() {
    local url="$1"
    echo "--- Fetching: $url ---"

    local http_code
    local tmpfile
    tmpfile=$(mktemp)

    http_code=$(curl --socks5-hostname "$TOR_PROXY" \
        -s -L \
        --max-time "$CURL_TIMEOUT" \
        --retry 2 \
        --retry-delay 3 \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0" \
        -o "$tmpfile" \
        -w "%{http_code}" \
        "$url" 2>/dev/null || echo "000")

    echo "HTTP Status: $http_code"

    if [ "$http_code" != "000" ] && [ -f "$tmpfile" ]; then
        # Extract title
        local title
        title=$(grep -oiP '(?<=<title>).*?(?=</title>)' "$tmpfile" 2>/dev/null | head -1 || echo "No title")
        echo "Title: $title"

        # Extract meta description
        local desc
        desc=$(grep -oiP '(?<=<meta name="description" content=")[^"]*' "$tmpfile" 2>/dev/null | head -1 || echo "No description")
        echo "Description: $desc"

        # Extract .onion links found on the page
        local onion_links
        onion_links=$(grep -oiE 'https?://[a-z2-7]{16,56}\.onion[^ "<>]*' "$tmpfile" 2>/dev/null | sort -u || true)
        if [ -n "$onion_links" ]; then
            echo "Onion links found on page:"
            echo "$onion_links" | while read -r link; do
                echo "  - $link"
            done
        fi

        # Output first 2000 chars of text content (strip HTML tags)
        echo "--- Content Preview ---"
        sed 's/<[^>]*>//g; s/&nbsp;/ /g; s/&amp;/\&/g; s/&lt;/</g; s/&gt;/>/g' "$tmpfile" \
            | tr -s '[:space:]' ' ' \
            | head -c 2000
        echo ""
    else
        echo "ERROR: Failed to fetch (timeout or connection refused)"
    fi

    rm -f "$tmpfile"
    echo "--- End: $url ---"
    echo ""
}

search_ahmia() {
    local query="$1"
    local encoded_query
    encoded_query=$(printf '%s' "$query" | sed 's/ /+/g; s/[^a-zA-Z0-9+._-]/%&/g')

    echo "Searching Ahmia for: $query"
    echo ""

    local results
    results=$(curl -s -L \
        --max-time 15 \
        "https://ahmia.fi/search/?q=${encoded_query}" 2>/dev/null || echo "")

    if [ -z "$results" ]; then
        echo "ERROR: Failed to reach Ahmia"
        return 1
    fi

    # Extract .onion URLs from Ahmia results
    local onion_urls
    onion_urls=$(echo "$results" | grep -oiE 'https?://[a-z2-7]{16,56}\.onion[^ "<>]*' | sort -u || true)

    if [ -n "$onion_urls" ]; then
        echo "Discovered .onion URLs:"
        echo "$onion_urls"
    else
        echo "No .onion URLs found for this query"
    fi
}

crawl_site() {
    local url="$1"
    local depth="${2:-1}"

    echo "Crawling: $url (depth: $depth)"
    echo ""

    # Fetch the initial page with metadata
    fetch_with_metadata "$url"

    if [ "$depth" -gt 1 ]; then
        # Extract .onion links from the page and fetch them too
        local page_content
        page_content=$(fetch_url "$url" 2>/dev/null || echo "")

        local found_links
        found_links=$(echo "$page_content" | grep -oiE 'https?://[a-z2-7]{16,56}\.onion[^ "<>]*' | sort -u | head -20 || true)

        if [ -n "$found_links" ]; then
            echo "=== Following ${depth}-deep links ==="
            echo ""
            echo "$found_links" | while read -r link; do
                sleep "$REQUEST_DELAY"
                if [ "$depth" -gt 2 ]; then
                    crawl_site "$link" $((depth - 1))
                else
                    fetch_with_metadata "$link"
                fi
            done
        fi
    fi
}

# Main dispatch
case "${1:-help}" in
    check-tor)
        check_tor
        ;;
    start-tor)
        start_tor
        ;;
    extract-onions)
        extract_onions
        ;;
    fetch)
        [ -z "${2:-}" ] && { echo "Usage: $0 fetch <url>"; exit 1; }
        fetch_with_metadata "$2"
        ;;
    search)
        [ -z "${2:-}" ] && { echo "Usage: $0 search <query>"; exit 1; }
        search_ahmia "$2"
        ;;
    crawl)
        [ -z "${2:-}" ] && { echo "Usage: $0 crawl <url> [depth]"; exit 1; }
        crawl_site "$2" "${3:-1}"
        ;;
    help|*)
        echo "darkweb-search.sh - Dark web OSINT search helper"
        echo ""
        echo "Commands:"
        echo "  check-tor               Check if Tor SOCKS proxy is running"
        echo "  start-tor               Start Tor and wait for bootstrap"
        echo "  extract-onions          Extract .onion URLs from stdin"
        echo "  fetch <url>             Fetch a URL through Tor with metadata"
        echo "  search <query>          Search Ahmia for .onion results"
        echo "  crawl <url> [depth]     Crawl an .onion site (depth 1-3)"
        echo ""
        echo "Examples:"
        echo "  $0 check-tor"
        echo "  $0 search 'data breach marketplace'"
        echo "  $0 fetch 'http://example2345....onion'"
        echo "  $0 crawl 'http://example2345....onion' 2"
        echo "  echo 'text with abc123.onion links' | $0 extract-onions"
        ;;
esac
