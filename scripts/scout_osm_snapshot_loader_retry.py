#!/usr/bin/env python3
"""Retry-hardened entrypoint for the Scout OSM snapshot loader.

Geofabrik's public download server can occasionally return transient gateway
errors. This wrapper retries only idempotent HTTP GET/HEAD downloads; it does
not retry Supabase RPC writes or change the loader's import semantics.
"""

from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

import scout_osm_snapshot_loader as loader

retry = Retry(
    total=6,
    connect=6,
    read=3,
    status=6,
    backoff_factor=2.0,
    status_forcelist=(429, 500, 502, 503, 504),
    allowed_methods=frozenset({"GET", "HEAD"}),
    respect_retry_after_header=True,
    raise_on_status=True,
)
adapter = HTTPAdapter(max_retries=retry)
loader.DOWNLOAD_SESSION.mount("https://", adapter)
loader.DOWNLOAD_SESSION.mount("http://", adapter)

if __name__ == "__main__":
    loader.main()
