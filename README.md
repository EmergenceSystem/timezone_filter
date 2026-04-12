# timezone_filter
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE.md)

An [em_filter](https://hex.pm/packages/em_filter) agent that returns the current local time, UTC offset, and DST status for any timezone via [timeapi.io](https://timeapi.io/) (free, no key required).

## Query

An IANA timezone identifier or a common city name. If the query contains `/` it is used as-is; otherwise a city alias table is checked (30 cities supported).

| Input form | Example |
|---|---|
| IANA zone | `Europe/Paris`, `America/New_York`, `Asia/Tokyo` |
| City name | `Paris`, `Tokyo`, `New York`, `London` |
| Short codes | `UTC`, `GMT` |

**Supported city aliases:** Paris, London, Berlin, Madrid, Rome, Amsterdam, Brussels, Zurich, Stockholm, Oslo, Helsinki, Moscow, Istanbul, Dubai, Tokyo, Beijing, Shanghai, Hong Kong, Singapore, Sydney, Melbourne, New York, Los Angeles, Chicago, Toronto, Montreal, Mexico City, São Paulo, Buenos Aires, UTC, GMT.

| Field | Example |
|---|---|
| title | `Europe/Paris — 10:04:55 2026-04-12` |
| resume | `UTC+02:00 CEST (DST until 2026-10-25T01:00:00)` |
| source | `timeapi.io` |

## Usage

**Via curl (direct to em_disco):**

```bash
# By city name
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "Tokyo", "capabilities": ["timezone"]}'

# By IANA zone
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "America/New_York", "capabilities": ["timezone"]}'

# UTC
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "UTC", "capabilities": ["timezone"]}'
```

**Via Erlang shell:**

```erlang
emquest_cli:query(<<"Paris">>).
emquest_cli:query(<<"Asia/Singapore">>).
```

## Installation

```bash
git clone https://github.com/EmergenceSystem/timezone_filter.git
cd timezone_filter
rebar3 shell --apps timezone_filter
```

Requires `em_disco` running on `localhost:8080` (configured in `emergence.conf`).

## Capabilities

`search`, `query`, `timezone`, `time`, `clock`, `dst`, `world`

## License

Apache 2.0 — see [LICENSE.md](LICENSE.md).
