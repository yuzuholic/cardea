"""a stand-in for the NAS: answers MCP initialize and recent_activity (basic memory) and
langfuse's health check on one port, so the tests can run anywhere. usage: python3 nas.py <port>
recent_activity knows one project, "demo", and replies as server-sent events like the real one."""
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
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if body.get("method") != "tools/call":
            return self.reply(200, {"jsonrpc": "2.0", "id": 1, "result": {"serverInfo": {"name": "fake-nas", "version": "1"}}})
        if body["params"]["arguments"].get("project") == "demo":
            rows = [{"type": "entity", "title": "Use CRDTs for sync", "permalink": "areas/sync/use-crdts-for-sync"}]
            result = {"content": [{"type": "text", "text": json.dumps(rows)}], "isError": False, "structuredContent": {"result": rows}}
        else:
            result = {"content": [{"type": "text", "text": "Project not found: 'x'"}], "isError": True}
        data = ("event: message\ndata: " + json.dumps({"jsonrpc": "2.0", "id": body["id"], "result": result}) + "\n\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/api/public/health":
            self.reply(200, {"status": "OK"})
        else:
            self.reply(404, {})

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
