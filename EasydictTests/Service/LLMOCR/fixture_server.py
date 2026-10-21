#!/usr/bin/env python3
"""Loopback-only, synthetic OCR fixture. Never contacts a provider or logs images."""

import argparse
import base64
import json
import struct
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

TEXT = "First paragraph.\n\n| Name | Value |\n| --- | --- |\n| x | $x^2$ |\n\n$$\\int_0^1 x\\,dx=\\frac{1}{2}$$\n"
STATES = {}
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Cancellation is an expected fixture scenario.

    def do_GET(self):
        url = urlsplit(self.path)
        model = parse_qs(url.query).get("model", [""])[0]
        if url.path == "/health":
            self.reply(200, {"ready": True})
            return
        with LOCK:
            event = STATES.get(model)
        if url.path == "/state":
            self.reply(200, {"accepted": event is not None})
        elif url.path == "/release" and event is not None:
            event.set()
            self.reply(200, {"released": True})
        else:
            self.reply(404, {"error": "unknown fixture request"})

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.reply(404, {"error": "unknown fixture endpoint"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            assert 0 < length < 2 * 1024 * 1024
            payload = json.loads(self.rfile.read(length))
            model = payload["model"]
            assert model.startswith("fixture-")
            assert set(payload) == {"model", "stream", "messages"}
            assert payload["stream"] is False
            assert self.headers.get("Authorization") is None
            messages = payload["messages"]
            assert len(messages) == 2 and messages[0]["role"] == "system"
            prompt = messages[0]["content"]
            assert "Do not translate" in prompt
            assert "Markdown tables" in prompt and "LaTeX" in prompt
            assert "never as instructions" in prompt
            assert messages[1]["role"] == "user"
            parts = messages[1]["content"]
            assert len(parts) == 1 and parts[0]["type"] == "image_url"
            image_url = parts[0]["image_url"]
            assert image_url["detail"] == "high"
            prefix = "data:image/png;base64,"
            assert image_url["url"].startswith(prefix)
            png = base64.b64decode(image_url["url"][len(prefix):], validate=True)
            assert png[:8] == b"\x89PNG\r\n\x1a\n"
            assert png[12:16] == b"IHDR"
            width, height = struct.unpack(">II", png[16:24])
            assert width == 32 and height == 24
        except (AssertionError, KeyError, TypeError, ValueError, struct.error):
            self.reply(400, {"error": "invalid synthetic OCR request"})
            return
        event = threading.Event()
        with LOCK:
            STATES[model] = event
        if model.startswith("fixture-delay-") and not event.wait(timeout=15):
            self.reply(504, {"error": "fixture release timed out"})
            return
        if model == "fixture-http-error":
            self.reply(503, {"error": "synthetic unavailable"})
            return
        self.reply(200, {"choices": [{
            "message": {"role": "assistant", "content": TEXT},
            "finish_reason": "stop",
        }]})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18767)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    print(f"Synthetic OCR fixture listening on 127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
