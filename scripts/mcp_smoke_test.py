#!/usr/bin/env python3

import json
import os
import selectors
import subprocess
import sys
import time


def _send(p: subprocess.Popen, msg: dict) -> None:
    assert p.stdin is not None
    p.stdin.write(json.dumps(msg, separators=(",", ":")) + "\n")
    p.stdin.flush()


def _recv_response(
    p: subprocess.Popen,
    sel: selectors.BaseSelector,
    target_id,
    timeout: float,
    stderr_lines: list[str],
) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        for key, _ in sel.select(timeout=0.2):
            line = key.fileobj.readline()
            if not line:
                continue
            line = line.strip()
            if not line:
                continue

            if key.fileobj is p.stderr:
                stderr_lines.append(line)
                continue

            try:
                obj = json.loads(line)
            except Exception:
                continue

            if obj.get("id") == target_id:
                return obj

    raise TimeoutError(f"timeout waiting for response id={target_id}")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "Usage: mcp_smoke_test.py <project-root> [typeName]\n"
            "Example: mcp_smoke_test.py /Users/me/MyProject Bezier3Segment",
            file=sys.stderr,
        )
        return 2

    project_root = os.path.abspath(argv[1])
    type_name = argv[2] if len(argv) >= 3 else "Bezier3Segment"

    if not os.path.isdir(project_root):
        print(f"Not a directory: {project_root}", file=sys.stderr)
        return 2

    aiq_mcp = subprocess.run(
        ["bash", "-lc", "command -v aiq-mcp"],
        text=True,
        capture_output=True,
    ).stdout.strip()
    if not aiq_mcp:
        print("aiq-mcp not found on PATH", file=sys.stderr)
        return 2

    p = subprocess.Popen(
        [aiq_mcp],
        cwd=project_root,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    sel = selectors.DefaultSelector()
    assert p.stdout is not None
    assert p.stderr is not None
    sel.register(p.stdout, selectors.EVENT_READ)
    sel.register(p.stderr, selectors.EVENT_READ)

    stderr_lines: list[str] = []

    try:
        # 1) initialize (params must exist and not be null)
        _send(p, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        init_resp = _recv_response(p, sel, 1, timeout=10.0, stderr_lines=stderr_lines)
        server_info = init_resp.get("result", {}).get("serverInfo", {})
        proto = init_resp.get("result", {}).get("protocolVersion")
        print("initialize.ok", f"server={server_info}", f"protocol={proto}")

        # 2) initialized notification (no response expected)
        _send(p, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        # 3) tools/list
        _send(p, {"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        tools_resp = _recv_response(p, sel, 2, timeout=10.0, stderr_lines=stderr_lines)
        tools = tools_resp.get("result", {}).get("tools", [])
        tool_names = [t.get("name") for t in tools]
        print("tools/list.ok", tool_names)

        # 4) tools/call -> query_type
        _send(
            p,
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "query_type",
                    "arguments": {"name": type_name, "membersLimit": 1},
                },
            },
        )
        call_resp = _recv_response(p, sel, 3, timeout=30.0, stderr_lines=stderr_lines)
        result = call_resp.get("result", {})
        content = result.get("content", [])
        text_items = [c.get("text", "") for c in content if c.get("type") == "text"]
        preview = (text_items[0] if text_items else "").replace("\n", " ")
        print("tools/call.ok", "isError=", result.get("isError"), "preview=", preview[:200])

        return 0

    finally:
        try:
            p.terminate()
        except Exception:
            pass
        try:
            p.wait(timeout=2)
        except Exception:
            pass

        if stderr_lines:
            print("\n== aiq-mcp stderr tail ==")
            for line in stderr_lines[-10:]:
                print(line)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
