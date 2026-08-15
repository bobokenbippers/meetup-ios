#!/usr/bin/env python3
"""Ingest normalized third-party events into Supabase cached_events.

This script is intentionally dependency-free so GitHub Actions can run it with
the stock Python runtime. It starts with Ticketmaster because that provider is
already configured for TestFlight builds; additional providers can append to the
same normalized rows later.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
import urllib.parse
import urllib.request
from typing import Any


SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://boyrqhbdkqzffvfokpri.supabase.co").rstrip("/")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
TICKETMASTER_API_KEY = os.environ.get("TICKETMASTER_API_KEY", "")

NYC_SEARCH_POINTS = [
    ("manhattan-midtown", 40.7580, -73.9855),
    ("lower-manhattan", 40.7128, -74.0060),
    ("williamsburg", 40.7081, -73.9571),
]

TICKETMASTER_CATEGORIES = [
    None,
    "Music",
    "Arts & Theatre",
    "Sports",
]


def require_env() -> None:
    missing = [
        name
        for name, value in {
            "SUPABASE_SERVICE_ROLE_KEY": SUPABASE_SERVICE_ROLE_KEY,
            "TICKETMASTER_API_KEY": TICKETMASTER_API_KEY,
        }.items()
        if not value
    ]
    if missing:
        raise SystemExit(f"Missing required env: {', '.join(missing)}")


def fetch_json(url: str, headers: dict[str, str] | None = None) -> dict[str, Any]:
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"HTTP {response.status}: {url}")
        return json.loads(response.read().decode("utf-8"))


def post_json(url: str, payload: list[dict[str, Any]]) -> None:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "apikey": SUPABASE_SERVICE_ROLE_KEY,
            "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"Supabase upsert failed: HTTP {response.status}")


def ticketmaster_url(latitude: float, longitude: float, category: str | None) -> str:
    query = {
        "apikey": TICKETMASTER_API_KEY,
        "geoPoint": geohash(latitude, longitude),
        "radius": "5",
        "unit": "miles",
        "size": "50",
        "sort": "relevance,desc",
        "startDateTime": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    if category:
        query["classificationName"] = category
    return "https://app.ticketmaster.com/discovery/v2/events.json?" + urllib.parse.urlencode(query)


def fetch_ticketmaster_events() -> list[dict[str, Any]]:
    rows: dict[tuple[str, str], dict[str, Any]] = {}
    for point_name, latitude, longitude in NYC_SEARCH_POINTS:
        for category in TICKETMASTER_CATEGORIES:
            url = ticketmaster_url(latitude, longitude, category)
            print(f"ticketmaster fetch point={point_name} category={category or 'all'}")
            data = fetch_json(url)
            events = data.get("_embedded", {}).get("events", [])
            for event in events:
                row = normalize_ticketmaster_event(event, category)
                if row:
                    rows[(row["source_name"], row["source_event_id"])] = row
    return list(rows.values())


def normalize_ticketmaster_event(event: dict[str, Any], category_hint: str | None) -> dict[str, Any] | None:
    venues = event.get("_embedded", {}).get("venues", [])
    venue = venues[0] if venues else {}
    location = venue.get("location") or {}
    try:
        lat = float(location["latitude"])
        lng = float(location["longitude"])
    except (KeyError, TypeError, ValueError):
        return None

    source_event_id = event.get("id")
    title = event.get("name")
    source_url = event.get("url")
    if not source_event_id or not title or not source_url:
        return None

    image_url = best_image_url(event.get("images") or [])
    starts_at = parse_ticketmaster_start(event.get("dates", {}).get("start", {}))
    address = format_ticketmaster_address(venue)
    category = category_hint or first_classification(event)

    return {
        "source_name": "ticketmaster",
        "source_event_id": source_event_id,
        "title": title,
        "venue_name": venue.get("name"),
        "address": address,
        "lat": lat,
        "lng": lng,
        "starts_at": starts_at,
        "source_url": source_url,
        "image_url": image_url,
        "category": category,
        "last_seen_at": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }


def parse_ticketmaster_start(start: dict[str, Any]) -> str | None:
    if start.get("dateTime"):
        return start["dateTime"]
    local_date = start.get("localDate")
    if not local_date:
        return None
    local_time = start.get("localTime") or "00:00:00"
    return f"{local_date}T{local_time}"


def format_ticketmaster_address(venue: dict[str, Any]) -> str | None:
    parts = [
        (venue.get("address") or {}).get("line1"),
        (venue.get("city") or {}).get("name"),
        (venue.get("state") or {}).get("stateCode"),
    ]
    present = [part for part in parts if part]
    return ", ".join(present) if present else None


def first_classification(event: dict[str, Any]) -> str | None:
    classifications = event.get("classifications") or []
    if not classifications:
        return None
    segment = classifications[0].get("segment") or {}
    return segment.get("name")


def best_image_url(images: list[dict[str, Any]]) -> str | None:
    if not images:
        return None
    sorted_images = sorted(images, key=lambda item: item.get("width", 0), reverse=True)
    return sorted_images[0].get("url")


def geohash(latitude: float, longitude: float, precision: int = 9) -> str:
    base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
    lat_range = [-90.0, 90.0]
    lon_range = [-180.0, 180.0]
    even = True
    bit = 0
    character_index = 0
    output = []

    while len(output) < precision:
        if even:
            midpoint = (lon_range[0] + lon_range[1]) / 2
            if longitude >= midpoint:
                character_index = (character_index << 1) + 1
                lon_range[0] = midpoint
            else:
                character_index <<= 1
                lon_range[1] = midpoint
        else:
            midpoint = (lat_range[0] + lat_range[1]) / 2
            if latitude >= midpoint:
                character_index = (character_index << 1) + 1
                lat_range[0] = midpoint
            else:
                character_index <<= 1
                lat_range[1] = midpoint
        even = not even
        bit += 1
        if bit == 5:
            output.append(base32[character_index])
            bit = 0
            character_index = 0
    return "".join(output)


def upsert_cached_events(rows: list[dict[str, Any]]) -> None:
    if not rows:
        print("no cached events to upsert")
        return
    url = f"{SUPABASE_URL}/rest/v1/cached_events?on_conflict=source_name,source_event_id"
    for chunk_start in range(0, len(rows), 100):
        chunk = rows[chunk_start : chunk_start + 100]
        post_json(url, chunk)
        print(f"upserted {len(chunk)} cached events")


def main() -> int:
    require_env()
    rows = fetch_ticketmaster_events()
    upsert_cached_events(rows)
    print(f"ingested {len(rows)} cached events")
    return 0


if __name__ == "__main__":
    sys.exit(main())
