#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""通过 GitHub Git Data API 提交并推送本地改动。

本机 git 的 schannel/openssl 到 github.com 的 TLS 都会被代理切断，
但 api.github.com 走 curl 是通的，所以改走 HTTP API 提交，效果与 git push 等价。
"""
import base64
import json
import os
import subprocess
import sys
import urllib.request

OWNER = os.environ.get("GH_OWNER", "Nocebook")
REPO = os.environ.get("GH_REPO", "LiquidGlass")
BRANCH = "main"
API = "https://api.github.com"


def token():
    out = subprocess.run(
        ["git", "credential", "fill"],
        input="protocol=https\nhost=github.com\n\n",
        capture_output=True, text=True,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    ).stdout
    for line in out.splitlines():
        if line.startswith("password="):
            return line[len("password="):].strip()
    raise SystemExit("no github credential")


def call(method, path, payload=None, tok=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + tok)
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as response:
        body = response.read()
        return json.loads(body) if body else {}


def main():
    files = sys.argv[1:]
    message = sys.stdin.read().strip() or "update"
    tok = token()

    ref = call("GET", f"/repos/{OWNER}/{REPO}/git/ref/heads/{BRANCH}", tok=tok)
    base_commit = ref["object"]["sha"]
    commit = call("GET", f"/repos/{OWNER}/{REPO}/git/commits/{base_commit}", tok=tok)
    base_tree = commit["tree"]["sha"]
    print("base", base_commit[:7])

    entries = []
    # 删除远端文件：Git Data API 的 tree 里把 sha 置 null 即可
    for path in os.environ.get("GH_DELETE", "").split(","):
        path = path.strip()
        if not path:
            continue
        entries.append({"path": path, "mode": "100644", "type": "blob", "sha": None})
        print("  del ", path)

    for path in files:
        with open(path, "rb") as handle:
            raw = handle.read()
        blob = call("POST", f"/repos/{OWNER}/{REPO}/git/blobs",
                    {"content": base64.b64encode(raw).decode(), "encoding": "base64"}, tok)
        entries.append({"path": path.replace("\\", "/"), "mode": "100644",
                        "type": "blob", "sha": blob["sha"]})
        print("  blob", path, len(raw), blob["sha"][:7])

    tree = call("POST", f"/repos/{OWNER}/{REPO}/git/trees",
                {"base_tree": base_tree, "tree": entries}, tok)
    new_commit = call("POST", f"/repos/{OWNER}/{REPO}/git/commits",
                      {"message": message, "tree": tree["sha"], "parents": [base_commit]}, tok)
    call("PATCH", f"/repos/{OWNER}/{REPO}/git/refs/heads/{BRANCH}",
         {"sha": new_commit["sha"], "force": False}, tok)
    print("pushed", new_commit["sha"][:7])


if __name__ == "__main__":
    main()
