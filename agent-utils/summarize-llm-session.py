#!/usr/bin/env python3
"""
Summarize openai-*.json LLM call logs into a readable session transcript.
Usage: summarize-llm-session.py <llm_log_dir> <output_file> [agent_label]
Reads all openai-*.json files, writes a markdown transcript, then deletes the JSON files.
"""
import glob
import json
import os
import sys


def fmt_args(raw):
    try:
        obj = json.loads(raw)
        # Compact for small args, pretty-print for large
        compact = json.dumps(obj)
        if len(compact) <= 120:
            return compact
        return json.dumps(obj, indent=2)
    except Exception:
        return raw


def summarize(llm_log_dir, output_file, agent_label):
    files = sorted(glob.glob(os.path.join(llm_log_dir, "openai-*.json")))
    if not files:
        return False

    lines = [f"# LLM Session: {agent_label}\n"]

    total_in = total_out = 0

    for i, fpath in enumerate(files, 1):
        try:
            with open(fpath) as f:
                data = json.load(f)
        except Exception as e:
            lines.append(f"## Turn {i} — ERROR reading {os.path.basename(fpath)}: {e}\n\n---\n")
            continue

        ts = data.get("timestamp", "")
        lines.append(f"## Turn {i}  <sup>{ts}</sup>\n")

        msg = (
            data.get("response", {})
            .get("choices", [{}])[0]
            .get("message", {})
        )
        reasoning = (msg.get("reasoning_content") or "").strip()
        content = (msg.get("content") or "").strip()
        tool_calls = msg.get("tool_calls") or []
        usage = data.get("response", {}).get("usage", {})
        pt = usage.get("prompt_tokens", 0)
        ct = usage.get("completion_tokens", 0)
        total_in += pt
        total_out += ct

        if reasoning:
            lines.append(f"> *{reasoning}*\n")

        if content:
            lines.append(f"{content}\n")

        if tool_calls:
            lines.append("**Tool calls:**")
            for tc in tool_calls:
                fn = tc.get("function", {})
                name = fn.get("name", "?")
                args = fmt_args(fn.get("arguments", "{}"))
                lines.append(f"  `{name}` {args}")
            lines.append("")

        lines.append(f"*{pt} in / {ct} out tokens*\n")
        lines.append("---\n")

    lines.append(f"\n**Session totals: {total_in} in / {total_out} out tokens**\n")

    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    with open(output_file, "w") as f:
        f.write("\n".join(lines))

    for fpath in files:
        os.unlink(fpath)

    return True


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <llm_log_dir> <output_file> [agent_label]", file=sys.stderr)
        sys.exit(1)

    ok = summarize(
        llm_log_dir=sys.argv[1],
        output_file=sys.argv[2],
        agent_label=sys.argv[3] if len(sys.argv) > 3 else "unknown",
    )
    sys.exit(0 if ok else 1)
