#!/usr/bin/env python3
"""Render a SwiftUI #Preview to PNG through Xcode's RenderPreview MCP tool.

usage: render_preview.py <project-relative .swift path> <out.png> [preview index] [--project PATH]

  project-relative path  as shown in Xcode's navigator, e.g. MyApp/Screens/Home.swift
  preview index          zero-based #Preview in the file (only 0 and 1 render reliably)
  --project              .xcodeproj/.xcworkspace; defaults to the first one in the cwd or its git root

Needs Xcode running. First use per agent triggers an approval prompt in Xcode's MCP
menu bar icon - the script exits with that message until the user approves.
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time


def find_project():
    roots = [os.getcwd()]
    try:
        roots.append(subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True, stderr=subprocess.DEVNULL).strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    for root in roots:
        for pattern in ("*.xcworkspace", "*.xcodeproj"):
            found = sorted(glob.glob(os.path.join(root, pattern)))
            if found:
                return found[0]
    raise SystemExit("no .xcodeproj or .xcworkspace found - pass --project")


args = sys.argv[1:]
project = None
if "--project" in args:
    i = args.index("--project")
    project = os.path.abspath(args[i + 1])
    del args[i:i + 2]
if len(args) < 2:
    raise SystemExit(__doc__)
path, out = args[0], args[1]
index = int(args[2]) if len(args) > 2 else 0
project = project or find_project()

proc = subprocess.Popen(
    ["xcrun", "mcpbridge"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)


def send(message):
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()


def wait(id):
    for line in proc.stdout:
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("id") == id:
            return message
    raise SystemExit("mcpbridge closed before replying - is Xcode running?")


def structured(reply):
    result = reply.get("result", {})
    if result.get("structuredContent"):
        return result["structuredContent"]
    for item in result.get("content", []):
        if item.get("type") == "text":
            try:
                return json.loads(item["text"])
            except json.JSONDecodeError:
                return {"error": item["text"]}
    return {}


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "render", "version": "0"}}})
wait(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

# opening the project is what triggers xcode's one-time approval prompt
send({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {
    "name": "XcodeOpenWorkspace", "arguments": {"path": project}}})
opened = structured(wait(2))
if "approve" in json.dumps(opened):
    proc.terminate()
    raise SystemExit("NEEDS APPROVAL: ask the user to approve the request from Xcode's MCP menu bar icon, then rerun")
workspace = opened.get("workspaceIdentifier", project)

reply = {}
for attempt in range(30):
    id = 3 + attempt
    send({"jsonrpc": "2.0", "id": id, "method": "tools/call", "params": {
        "name": "RenderPreview",
        "arguments": {"sourceFilePath": path, "previewDefinitionIndexInFile": index,
                      "timeout": 300, "workspaceIdentifier": workspace}}})
    reply = wait(id)
    text = json.dumps(reply)
    # a freshly written file takes a few seconds to reach xcode's synced folder
    if "Waiting for packages" not in text and "not found in project structure" not in text:
        break
    time.sleep(10)
proc.terminate()

result = structured(reply)
snapshot = result.get("previewSnapshotPath")
if not snapshot:
    message = result.get("error") or result.get("data") or json.dumps(reply)
    try:
        message = json.loads(message).get("data", message)
    except (json.JSONDecodeError, TypeError, AttributeError):
        pass
    # build failures carry the whole frontend command line after the diagnostics
    print(str(message).split("Failed frontend command")[0][:3000])
    raise SystemExit(1)

os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
shutil.copy(snapshot, out)
device = (result.get("renderedDestination") or {}).get("deviceModelName")
print(f"{out}  [{result.get('displayName')}]  {device}")
