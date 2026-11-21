"""Pooled HTTPS JSON fetcher with strict byte and deadline ceilings."""

import gzip
import http.client
import io
import json
import threading
import time
import urllib.error
import urllib.request
import zlib
from urllib.parse import urlsplit

from .constants import (
    MAX_BODY_BYTES,
    MAX_DECOMPRESSED_BYTES,
    READ_CHUNK_BYTES,
    REQUEST_TIMEOUT,
    UNTIMED_BODY_BUDGET,
)

NETWORK_ERRORS = (
    urllib.error.URLError,
    http.client.HTTPException,
    OSError,
    ValueError,
    TimeoutError,
)

_pool = threading.local()


def take_connection(host, timeout):
    """Return (connection, reused). A reused one may already be half dead."""
    connections = getattr(_pool, "connections", None)
    if connections is None:
        connections = _pool.connections = {}
    connection = connections.get(host)
    reused = connection is not None
    if connection is None:
        connection = connections[host] = http.client.HTTPSConnection(
            host, timeout=timeout
        )
    connection.timeout = timeout
    if connection.sock is not None:
        try:
            connection.sock.settimeout(timeout)
        except OSError:
            pass
    return connection, reused


def drop_connection(host):
    connections = getattr(_pool, "connections", None) or {}
    connection = connections.pop(host, None)
    if connection is not None:
        try:
            connection.close()
        except OSError:
            pass


def read_body(response, deadline):
    """Read response body bounded in bytes and wall-clock time."""
    chunks = []
    total = 0
    while True:
        if time.time() >= deadline:
            raise TimeoutError("response body outlived its deadline")
        chunk = response.read1(READ_CHUNK_BYTES)
        if not chunk:
            return b"".join(chunks)
        total += len(chunk)
        if total > MAX_BODY_BYTES:
            raise ValueError("response body over %d bytes" % MAX_BODY_BYTES)
        chunks.append(chunk)


def gunzip_body(payload):
    """Expand a gzip body, refusing one that expands out of all proportion."""
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(payload)) as stream:
            body = stream.read(MAX_DECOMPRESSED_BYTES + 1)
    except EOFError:
        raise ValueError("response ended mid-gzip-stream")
    except zlib.error as error:
        raise ValueError("response is not readable gzip: %s" % error)
    if len(body) > MAX_DECOMPRESSED_BYTES:
        raise ValueError(
            "response expands past %d bytes" % MAX_DECOMPRESSED_BYTES
        )
    return body


def read_json_url(url, deadline=None):
    """Fetch and parse one JSON document over keep-alive HTTPS."""
    timeout = REQUEST_TIMEOUT
    if deadline is not None:
        timeout = max(1.0, min(REQUEST_TIMEOUT, deadline - time.time()))

    parts = urlsplit(url)
    host = parts.netloc
    target = parts.path + ("?" + parts.query if parts.query else "")
    headers = {
        "User-Agent": "Python-urllib/%s" % urllib.request.__version__,
        "Accept-Encoding": "gzip",
        "Connection": "keep-alive",
    }

    if deadline is None:
        body_deadline = time.time() + UNTIMED_BODY_BUDGET
    else:
        body_deadline = max(deadline, time.time() + timeout)

    while True:
        connection, reused = take_connection(host, timeout)
        try:
            connection.request("GET", target, headers=headers)
            response = connection.getresponse()
        except (http.client.HTTPException, OSError):
            drop_connection(host)
            if reused:
                continue
            raise

        if response.status != 200:
            drop_connection(host)
            raise urllib.error.HTTPError(
                url, response.status, response.reason, response.headers, None
            )

        try:
            payload = read_body(response, body_deadline)
        except (http.client.HTTPException, OSError, ValueError):
            drop_connection(host)
            raise
        break

    if response.headers.get("Content-Encoding", "").lower() == "gzip":
        try:
            payload = gunzip_body(payload)
        except (OSError, ValueError):
            drop_connection(host)
            raise
    return json.loads(payload.decode("utf-8"))
