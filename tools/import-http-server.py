#!/usr/bin/env python3
import argparse
import functools
import http.server
import pathlib
import re
import socketserver
import urllib.parse

ALLOWED_FILE_RE = re.compile(
    r"^(?P<prefix>[A-Za-z0-9_.@-]+)-(?P<token>[A-Za-z0-9]{6,64})\.(surge\.conf|clash\.yaml|loon\.conf|egern\.uri)$"
)


class ImportFileHandler(http.server.SimpleHTTPRequestHandler):
    def _validated_name(self):
        parsed = urllib.parse.urlparse(self.path)
        requested = parsed.path.lstrip("/")
        if "/" in requested or requested in ("", ".", ".."):
            return None
        match = ALLOWED_FILE_RE.fullmatch(requested)
        if match is None:
            return None

        token_in_query = urllib.parse.parse_qs(parsed.query).get("token", [""])[0]
        if token_in_query != match.group("token"):
            return None
        return requested

    def list_directory(self, path):
        self.send_error(403, "Directory listing is disabled")
        return None

    def do_GET(self):
        if self._validated_name() is None:
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self):
        if self._validated_name() is None:
            self.send_error(404)
            return
        super().do_HEAD()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--directory", required=True)
    args = parser.parse_args()

    directory = pathlib.Path(args.directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)

    handler = functools.partial(ImportFileHandler, directory=str(directory))
    with socketserver.TCPServer((args.bind, args.port), handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
