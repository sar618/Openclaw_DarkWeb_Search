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

Before executing any searches, verify Tor is running:

```bash
# Check if Tor is running
pgrep -x tor || tor & sleep 3

# Verify SOCKS proxy is reachable
curl --socks5-hostname 127.0.0.1:9050 -s -o /dev/null -w "%{http_code}" https://check.torproject.org
```

If Tor is not running, start it and wait for bootstrap to complete.

## How It Works

The search follows a three-phase approach:

### Phase 1: Surface Web Discovery

Use the `web_search` tool to find .onion addresses indexed on the surface web. Search across multiple sources:

1. **Direct search queries** - Search for the topic combined with terms like:
   - `"<topic>" site:.onion`
   - `"<topic>" .onion link`
   - `"<topic>" hidden service tor`
   - `"<topic>" onion address`

2. **Known aggregators** - Query Tor-accessible search engines via SOCKS proxy:
   - **Ahmia** - `http://juhanurmihxlp77nkq76byazcldy2hlmovfu2epvl5ankdibsot4csyd.onion/search/?q=<topic>` (Tor search engine)
   - **TORCH** - `http://xmh57jrknzkhv6y3ls3ubitzfqnkrwxhopf5aygthi7d6rplyvk3noyd.onion/cgi-bin/omega/omega?P=<topic>` (established dark web search engine)
   - **DuckDuckGo** - `http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion` (privacy-focused search with .onion front-end, uses POST method with `name="q"`)
   - **Haystack** - `http://haystak5njsmn2hqkewecpaxetahtwhsbsa64jom2k22z5afxhnpxfid.onion/?q=<topic>` (dark web search engine, query parameter: `q`)
   - **The Hidden Wiki** - `http://6nhmgdpnyoljh5uzr5kwlatx2u3diou4ldeommfxjz3wkhalzgjqxzqd.onion` (curated directory of .onion links, browse by category)
   - **Dark.fail** - `http://darkfailenbsdla5mal2mxn2uz66od5vtzd5qozslagrfzachha3f3id.onion` (verified .onion link directory, no search - browse categories)

3. **Extract .onion URLs** from all results using pattern:
   - `[a-z2-7]{56}\.onion` (v3 onion addresses)
   - `[a-z2-7]{16}\.onion` (v2, deprecated but may still appear)

### Phase 2: Tor-Based Crawling

For each discovered .onion URL, use the `exec` tool to fetch content through Tor:

```bash
# Fetch a single .onion page through Tor SOCKS proxy
curl --socks5-hostname 127.0.0.1:9050 \
  -s -L \
  --max-time 30 \
  --retry 2 \
  -H "User-Agent: Mozilla/5.0" \
  "http://<onion-address>"
```

Key parameters:
- `--socks5-hostname` routes DNS through Tor (critical - do NOT use `--socks5` as it leaks DNS)
- `--max-time 30` prevents hanging on unresponsive services (Tor is slow)
- `-L` follows redirects within the Tor network
- `--retry 2` retries on transient failures

For each .onion site that responds:
1. Fetch the landing page
2. Extract the page title, description, and key content
3. Extract any additional .onion links found on the page (for deeper crawling if requested)
4. Record the HTTP status code and basic metadata

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

## Crawling Depth

- **Default (depth=1):** Only fetch the landing page of each discovered .onion site
- **Deep (depth=2):** Also follow links found on landing pages to discover additional .onion sites (one hop)
- **Maximum (depth=3):** Follow links up to two hops from the original discovery (use with caution - this generates significant traffic)

When the user asks for a "deep search" or "thorough search", use depth=2. Only use depth=3 if explicitly requested.

## Safety Guidelines

1. **Never submit forms or interact with services** - only read/fetch page content
2. **Never download files** from .onion sites - only retrieve HTML content
3. **Never create accounts** or authenticate on any dark web service
4. **Always use `--socks5-hostname`** (not `--socks5`) to prevent DNS leaks
5. **Rate limit requests** - wait 2-3 seconds between requests to avoid overloading Tor circuits
6. **Timeout aggressively** - .onion sites are often slow or offline; don't wait more than 30 seconds
7. **Log all accessed URLs** for audit trail purposes
8. **Respect robots.txt** where present on .onion sites
9. **Never attempt to deanonymize** hidden service operators or users

## IP Protection Rules

**Critical: Protect the user's IP address at all times.**

### Mandatory Requirements
- **Verify Tor before ANY dark web activity** - Run `check-tor` via the helper script before Phase 2 crawling
- **All .onion traffic MUST use Tor SOCKS proxy** (127.0.0.1:9050)
- **All DNS queries MUST route through Tor** - Always use `--socks5-hostname` (not `--socks5`) to prevent DNS leaks
- **Surface web queries** - Use Brave API (web_search) for surface web discovery - this is acceptable
- **NEVER fetch clearnet URLs directly** during Tor-based crawling - stay within .onion ecosystem once in Phase 2

### Verification Steps
Before executing any .onion fetches:
```bash
# 1. Check Tor is running
bash darkweb-search.sh check-tor

# 2. Verify SOCKS proxy responds with success
curl --socks5-hostname 127.0.0.1:9050 -s -o /dev/null -w "%{http_code}" https://check.torproject.org
# Expected: 200
```

If Tor verification fails, **abort the search** and alert the user.

## Example Interaction

**User:** Search the dark web for any mentions of "AcmeCorp" data breach

**Agent actions:**
1. Verify Tor is running (start if needed)
2. Search surface web: `"AcmeCorp" .onion`, `"AcmeCorp" data breach tor hidden service`
3. Search Ahmia: `https://ahmia.fi/search/?q=AcmeCorp+data+breach`
4. Collect all discovered .onion URLs
5. Fetch each .onion site through Tor proxy
6. Extract and summarize relevant content
7. Present structured report with findings

## Troubleshooting

- **Tor won't start:** Check if port 9050 is already in use: `ss -tlnp | grep 9050`
- **All sites timeout:** Tor may still be bootstrapping. Wait 10-15 seconds and retry.
- **Connection refused:** Ensure Tor is configured as a SOCKS proxy (default in most installations).
- **Slow responses:** Normal for Tor. The skill uses 30-second timeouts to accommodate this.
