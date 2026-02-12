---
metadata.openclaw:
  emoji: 🕵️
  requires:
    bins: [tor, curl]
    env: []
    config: []
  install:
    - apt-get install -y tor curl
  os: [linux, darwin]
---

# Dark Web Search (OSINT)

Search the dark web (Tor network) for .onion sites as part of OSINT investigations. This skill combines surface-web search engines with Tor-based crawling to discover and retrieve content from .onion addresses.

**Important:** This skill is intended exclusively for authorized OSINT investigations, threat intelligence, security research, and journalism. Always ensure you have proper authorization before conducting dark web research. Comply with all applicable laws and organizational policies.

## When to Use

Use this skill when the user asks to:
- Search for .onion sites or dark web content
- Perform OSINT reconnaissance on Tor hidden services
- Find dark web mirrors or hidden services for a given topic
- Monitor dark web sources for threat intelligence
- Discover .onion addresses related to a subject

## Prerequisites

1. **Tor must be installed and running** as a SOCKS5 proxy on `127.0.0.1:9050`
2. **curl** must be available for making requests through Tor

Before executing any searches, use the helper script to verify Tor:

```bash
# Check Tor is running, SOCKS proxy works, and DNS leak check passes
bash darkweb-search.sh check-tor

# If Tor is not running, start it (tries systemctl first, falls back to direct)
bash darkweb-search.sh start-tor
```

The `check-tor` command verifies three things:
1. The `tor` process is running
2. The SOCKS5 proxy on `127.0.0.1:9050` returns HTTP 200
3. Traffic is confirmed routed through Tor via the `check.torproject.org/api/ip` API (`"IsTor":true`)

The `start-tor` command prefers `systemctl start tor` when available, falling back to direct `tor &` invocation, then waits up to 60 seconds for bootstrap to complete.

If Tor verification fails, **abort the search** and alert the user.

## How It Works

The search follows a three-phase approach:

### Phase 1: Surface Web Discovery

Use the `web_search` tool to find .onion addresses indexed on the surface web. Search across multiple sources:

1. **Direct search queries** - Search for the topic combined with terms like:
   - `"<topic>" site:.onion`
   - `"<topic>" .onion link`
   - `"<topic>" hidden service tor`
   - `"<topic>" onion address`

2. **Multi-engine search** - The `search` command tries multiple strategies automatically:

   > **Note:** Most .onion search engines (Ahmia, TORCH, Haystack) now require JavaScript to render results. The script uses non-JS approaches where possible.

   The script runs four strategies in sequence:
   1. **Ahmia JSON API** - Requests `?format=json` from Ahmia (no JS required)
   2. **Ahmia .onion mirror** - Queries the Tor-native Ahmia address directly
   3. **TORCH .onion** - Queries TORCH search engine via Tor
   4. **Surface web discovery** - Searches DuckDuckGo HTML (lite, no JS) for `.onion` references on the clearnet

   Results from all strategies are deduplicated and combined.

   ```bash
   bash darkweb-search.sh search "<topic>"
   ```

   **Known .onion directories** (for manual browsing via `crawl`):
   - **The Hidden Wiki** - `http://6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion` (curated directory, browse by category)
   - **Dark.fail** - `http://darkfailenbsdla5mal2mxn2uz66od5vtzd5qozslagrfzachha3f3id.onion` (verified link directory, browse only - no search)

   If the `search` command returns no results, try crawling these directories or use the agent's `web_search` tool for broader surface web discovery.

3. **Extract .onion URLs** from all results using strict pattern matching:
   - `[a-z2-7]{56}\.onion` (v3 onion addresses - exactly 56 characters)
   - `[a-z2-7]{16}\.onion` (v2 onion addresses - exactly 16 characters, deprecated but may still appear)

   The script's `extract-onions` command can extract these from any text:
   ```bash
   echo "text with onion URLs" | bash darkweb-search.sh extract-onions
   ```

### Phase 2: Tor-Based Crawling

For each discovered .onion URL, use the helper script to fetch content through Tor:

```bash
# Fetch a single .onion page with metadata extraction
bash darkweb-search.sh fetch "http://<onion-address>"

# Crawl a site and follow links (depth 1-3)
bash darkweb-search.sh crawl "http://<onion-address>" 2
```

The script uses the following curl configuration for all Tor requests:
- `--socks5-hostname 127.0.0.1:9050` routes both traffic and DNS through Tor (critical - prevents DNS leaks)
- `--max-time 30` prevents hanging on unresponsive services
- `-L` follows redirects within the Tor network
- `--retry 2 --retry-delay 3` retries on transient failures
- `--` before URLs prevents flag injection from URLs starting with `-`
- User-Agent set to `Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0`

For each .onion site that responds, the `fetch` command extracts:
1. HTTP status code
2. Page title (from `<title>` tag)
3. Meta description
4. Any .onion links found on the page
5. First 2000 characters of text content (HTML stripped)

### Phase 3: Analysis and Reporting

Compile results into a structured report:

```
## Dark Web Search Results: <topic>

### Summary
- Total .onion URLs discovered: <count>
- Responsive sites: <count>
- Unresponsive/offline: <count>

### Discovered Sites

#### 1. <Site Title or "Untitled">
- **Address:** <full .onion URL>
- **Status:** <Online/Offline>
- **Description:** <extracted description or summary of content>
- **Discovered via:** <source - e.g., Ahmia, surface web search, crawled link>

...
```

## Script Commands Reference

| Command | Description |
|---------|-------------|
| `check-tor` | Verify Tor is running, SOCKS proxy works, and DNS leak check passes |
| `start-tor` | Start Tor (systemctl preferred, falls back to direct) and wait for bootstrap |
| `extract-onions` | Extract unique v2/v3 .onion addresses from stdin |
| `fetch <url>` | Fetch a URL through Tor with full metadata extraction |
| `search <query>` | Multi-engine .onion search: Ahmia JSON API, Ahmia .onion, TORCH, surface web (auto URL-encoded) |
| `crawl <url> [depth]` | Crawl an .onion site with link following (depth 1-3) |

## Crawling Depth

- **Default (depth=1):** Only fetch the landing page of each discovered .onion site
- **Deep (depth=2):** Also follow links found on landing pages to discover additional .onion sites (one hop)
- **Maximum (depth=3):** Follow links up to two hops from the original discovery (use with caution - this generates significant traffic)

The script enforces a hard cap of depth=3 (`MAX_CRAWL_DEPTH`). Values above 3 are automatically capped with a warning.

The crawler deduplicates visited URLs across the entire crawl session, preventing infinite loops when sites link to each other (e.g., site A links to site B which links back to site A). Already-visited URLs are skipped with a log message.

At each depth level, the crawler follows up to 20 .onion links discovered on the page, with a 2-second delay (`REQUEST_DELAY`) between requests.

When the user asks for a "deep search" or "thorough search", use depth=2. Only use depth=3 if explicitly requested.

## Safety Guidelines

1. **Never submit forms or interact with services** - only read/fetch page content
2. **Never download files** from .onion sites - only retrieve HTML content
3. **Never create accounts** or authenticate on any dark web service
4. **Always use `--socks5-hostname`** (not `--socks5`) to prevent DNS leaks
5. **Rate limit requests** - the script enforces a 2-second delay between requests during crawling
6. **Timeout aggressively** - the script uses a 30-second timeout (`CURL_TIMEOUT`) for all fetches
7. **Log all accessed URLs** for audit trail purposes
8. **Never attempt to deanonymize** hidden service operators or users

## IP Protection Rules

**Critical: Protect the user's IP address at all times.**

### Mandatory Requirements

- **Verify Tor before ANY dark web activity** - Run `bash darkweb-search.sh check-tor` before Phase 2 crawling
- **All .onion traffic MUST use Tor SOCKS proxy** (127.0.0.1:9050) via `--socks5-hostname`
- **All DNS queries MUST route through Tor** - The script uses `--socks5-hostname` (not `--socks5`) for every curl call
- **Ahmia searches are routed through Tor** - The `search` command uses the SOCKS proxy for Ahmia queries
- **Surface web queries** - Use Brave API (web_search) for surface web discovery - this is acceptable
- **NEVER fetch clearnet URLs directly** during Tor-based crawling - stay within .onion ecosystem once in Phase 2

### Verification Steps

Before executing any .onion fetches:

```bash
# Full verification: Tor process + SOCKS proxy + DNS leak check
bash darkweb-search.sh check-tor
# Expected output:
#   OK: Tor SOCKS proxy is reachable and functional
#   OK: DNS leak check passed - traffic confirmed routed through Tor
```

If the DNS leak check returns a WARNING, investigate before proceeding - traffic may not be properly routed through Tor.

### Temp File Cleanup

The script tracks all temporary files and cleans them up automatically on exit, interrupt (Ctrl+C), or termination signals via `trap cleanup EXIT INT TERM`. No manual cleanup is needed.

## Example Interaction

**User:** Search the dark web for any mentions of "AcmeCorp" data breach

**Agent actions:**
1. Verify Tor is running: `bash darkweb-search.sh check-tor` (start if needed with `start-tor`)
2. Search surface web: `"AcmeCorp" .onion`, `"AcmeCorp" data breach tor hidden service`
3. Search Ahmia via Tor: `bash darkweb-search.sh search "AcmeCorp data breach"`
4. Collect all discovered .onion URLs
5. Fetch each .onion site through Tor: `bash darkweb-search.sh fetch "<url>"` for each
6. Extract and summarize relevant content
7. Present structured report with findings

## Troubleshooting

- **Tor won't start:** Check if port 9050 is already in use: `ss -tlnp | grep 9050`
- **All sites timeout:** Tor may still be bootstrapping. Wait 10-15 seconds and retry.
- **Connection refused:** Ensure Tor is configured as a SOCKS proxy (default in most installations).
- **Slow responses:** Normal for Tor. The script uses 30-second timeouts to accommodate this.
- **DNS leak warning:** The `check-tor` command could not confirm `"IsTor":true` from the Tor Project API. Verify your Tor configuration and ensure no proxy bypass is occurring.
- **systemctl start tor fails:** The script falls back to direct `tor &` invocation. Ensure the `tor` binary is in your PATH and you have sufficient permissions.
- **Search returns no results:** Most .onion search engines now require JavaScript. The script uses Ahmia's JSON API and DuckDuckGo HTML (lite) to avoid this. If still no results, try crawling known directories (Hidden Wiki, Dark.fail) or use the agent's `web_search` tool for surface web `.onion` discovery.
