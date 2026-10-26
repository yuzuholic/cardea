"""a stand-in for the NAS: answers MCP initialize (basic memory) and langfuse's health
check on one port, so the prompt tests can run anywhere. usage: python3 nas.py <port>"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.reply(200, {"jsonrpc": "2.0", "id": 1, "result": {"serverInfo": {"name": "fake-nas", "version": "1"}}})

    def do_GET(self):
        if self.path == "/api/public/health":
            self.reply(200, {"status": "OK"})
        else:
            self.reply(404, {})

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
