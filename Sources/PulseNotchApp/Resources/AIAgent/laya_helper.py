"""Pulse Notch Laya helper.

Answers typed System One questions with laya-mlx over private standard
input/output pipes. Each request and response is one line of JSON:

    request:  {"v": 1, "id": "<id>", "state": ..., "questions": {...}}
    response: {"v": 1, "id": "<id>", "ok": true, "result": {...}}
              {"v": 1, "id": "<id>", "ok": false, "error": "<message>"}

After loading the checkpoint the helper writes a response with the id "ready".
The helper never opens network connections, and it receives no desktop-control
permissions: macOS grants those to Pulse Notch, not to this interpreter.
"""

import json
import os
import sys

PROTOCOL_VERSION = 1


def _plain(value):
    """Converts NumPy scalars in results to plain JSON numbers."""
    if hasattr(value, "item"):
        return value.item()
    raise TypeError(f"{type(value).__name__} is not JSON serializable")


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write("usage: laya_helper.py <checkpoint directory>\n")
        return 2

    # Reserve the real standard output for protocol messages and point file
    # descriptor 1 at standard error, so output from Python or native libraries
    # cannot corrupt the stream.
    protocol = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
    os.dup2(2, 1)
    sys.stdout = sys.stderr

    def send(message):
        message["v"] = PROTOCOL_VERSION
        protocol.write(json.dumps(message, separators=(",", ":"), default=_plain) + "\n")
        protocol.flush()

    try:
        import laya_mlx

        agent = laya_mlx.load(sys.argv[1])
    except Exception as error:  # noqa: BLE001 - reported to the app, then exit
        send({"id": "ready", "ok": False, "error": f"Could not load Laya: {error}"})
        return 1

    send({"id": "ready", "ok": True, "result": {"model": "laya-rl-agent"}})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
            if request.get("v") != PROTOCOL_VERSION:
                raise ValueError(f"unsupported protocol version {request.get('v')}")
            result = agent.predict(request["state"], request["questions"])
            send({"id": request_id, "ok": True, "result": result})
        except Exception as error:  # noqa: BLE001 - each request fails independently
            send({"id": request_id, "ok": False, "error": str(error)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
