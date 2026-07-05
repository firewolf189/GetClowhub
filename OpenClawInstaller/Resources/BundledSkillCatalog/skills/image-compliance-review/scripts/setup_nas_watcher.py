#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Configure the NAS image watcher from a mounted folder name or path."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional


APP_DIR = Path.home() / ".image-compliance-review"
LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"


def json_dump(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    tmp_path.replace(path)


def safe_id(value: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-")
    return safe or "main"


def script_dir() -> Path:
    return Path(__file__).resolve().parent


def skill_dir() -> Path:
    return script_dir().parent


def watcher_script() -> Path:
    return script_dir() / "watch_nas_images.py"


def find_openclaw(explicit: Optional[str] = None) -> str:
    if explicit:
        path = Path(explicit).expanduser()
        if path.exists():
            return str(path)
        raise SystemExit(f"OpenClaw binary not found: {path}")
    found = shutil.which("openclaw")
    if found:
        return found
    common = Path.home() / ".npm-global" / "bin" / "openclaw"
    if common.exists():
        return str(common)
    raise SystemExit("Could not find openclaw. Install OpenClaw or pass --openclaw /absolute/path.")


def run_json(command: list[str]) -> Any | None:
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def load_agents(openclaw: str) -> list[dict[str, Any]]:
    payload = run_json([openclaw, "agents", "list", "--json"])
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    return []


def choose_agent(agents: list[dict[str, Any]], requested: Optional[str]) -> dict[str, Any]:
    if requested:
        for agent in agents:
            if agent.get("id") == requested or agent.get("name") == requested:
                return agent
        workspace = Path.home() / ".openclaw" / f"workspace-{requested}"
        return {"id": requested, "name": requested, "workspace": str(workspace), "isDefault": False}
    for agent in agents:
        if agent.get("isDefault"):
            return agent
    if agents:
        return agents[0]
    return {"id": "main", "name": "main", "workspace": str(Path.home() / ".openclaw" / "workspace-main")}


def iter_dirs(root: Path, max_depth: int) -> list[Path]:
    results: list[Path] = []
    if not root.exists():
        return results
    stack: list[tuple[Path, int]] = [(root, 0)]
    while stack:
        current, depth = stack.pop()
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    if not entry.is_dir(follow_symlinks=False):
                        continue
                    path = Path(entry.path)
                    results.append(path)
                    if depth + 1 < max_depth:
                        stack.append((path, depth + 1))
        except (OSError, PermissionError):
            continue
    return results


def resolve_watch_dir(folder_name: Optional[str], explicit_path: Optional[str], max_depth: int) -> Path:
    if explicit_path:
        path = Path(explicit_path).expanduser()
        if path.exists() and path.is_dir():
            return path.resolve()
        raise SystemExit(f"Watch directory not found: {path}")

    if not folder_name:
        raise SystemExit("Pass --folder-name or --watch-dir.")

    maybe_path = Path(folder_name).expanduser()
    looks_like_path = maybe_path.is_absolute() or "/" in folder_name
    if looks_like_path and maybe_path.exists() and maybe_path.is_dir():
        return maybe_path.resolve()

    roots = [Path("/Volumes")]
    candidates: list[Path] = []
    for root in roots:
        for path in iter_dirs(root, max_depth=max_depth):
            if path.name == folder_name:
                candidates.append(path.resolve())

    unique = sorted({str(path): path for path in candidates}.values(), key=str)
    if len(unique) == 1:
        return unique[0]
    if len(unique) > 1:
        print("Multiple mounted folders matched. Ask the user to choose one:", file=sys.stderr)
        for index, path in enumerate(unique, start=1):
            print(f"{index}. {path}", file=sys.stderr)
        raise SystemExit(3)

    visible = [str(path) for path in iter_dirs(Path("/Volumes"), max_depth=2)[:80]]
    print(f"No mounted folder named {folder_name!r} was found under /Volumes.", file=sys.stderr)
    if visible:
        print("Visible mounted directories:", file=sys.stderr)
        for path in visible:
            print(f"- {path}", file=sys.stderr)
    raise SystemExit(2)


def watcher_root(agent_id: str) -> Path:
    return APP_DIR / "watchers" / safe_id(agent_id)


def build_config(
    *,
    watch_dir: Path,
    openclaw: str,
    agent_id: str,
    agent_workspace: Path,
    poll_seconds: int,
    settle_seconds: int,
) -> dict[str, Any]:
    root = watcher_root(agent_id)
    output_root = agent_workspace / "review-output"
    return {
        "agent_id": agent_id,
        "agent_workspace": str(agent_workspace),
        "watch_dir": str(watch_dir),
        "state_file": str(root / "state.json"),
        "batch_dir": str(root / "batches"),
        "batch_input_dir": str(root / "batch-inputs"),
        "log_file": str(root / "watcher.log"),
        "output_root": str(output_root),
        "cleanup_batch_input": "on_success",
        "poll_seconds": poll_seconds,
        "settle_seconds": settle_seconds,
        "batch_limit": 8,
        "ignore_dir_names": [
            ".image-review-watcher",
            "review-output",
            "review_reports",
            "__MACOSX",
        ],
        "trigger": {
            "enabled": True,
            "cwd": str(agent_workspace),
            "command": [
                openclaw,
                "agent",
                "--agent",
                agent_id,
                "--timeout",
                "1800",
                "--session-id",
                "image-review-{batch_id}",
                "--json",
                "--message",
                (
                    "请使用 image-compliance-review 技能审核新增图片。"
                    "NAS 原始图片根目录：{watch_dir}。"
                    "本批隔离输入目录：{batch_input_dir}。"
                    "本批新增图片清单 JSON：{batch_file}。"
                    "审核规则：{rules_file}。"
                    "只审核本批隔离输入目录里的图片；finalize 时 --input 必须使用 {batch_input_dir}，不要使用 NAS 根目录。"
                    "finalize 时 --output-dir 必须使用 {run_output_dir}，并用 --report-output 写到 {batch_report_file}。"
                    "每批必须保留结构化结果：{review_results_file}。"
                ),
            ],
        },
    }


def build_plist(label: str, config_path: Path, agent_id: str) -> dict[str, Any]:
    root = watcher_root(agent_id)
    return {
        "Label": label,
        "ProgramArguments": [
            "/usr/bin/python3",
            str(watcher_script()),
            "--project-dir",
            str(skill_dir()),
            "--config",
            str(config_path),
        ],
        "WorkingDirectory": str(skill_dir()),
        "RunAtLoad": True,
        "KeepAlive": True,
        "StandardOutPath": str(root / "launchd.out.log"),
        "StandardErrorPath": str(root / "launchd.err.log"),
    }


def write_plist(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        plistlib.dump(payload, handle)


def run_watcher(args: list[str]) -> int:
    return subprocess.run(["/usr/bin/python3", str(watcher_script()), *args]).returncode


def install_launch_agent(plist_path: Path, label: str, start: bool) -> None:
    LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
    installed_path = LAUNCH_AGENTS_DIR / plist_path.name
    shutil.copy2(plist_path, installed_path)
    if not start:
        return
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", domain, str(installed_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run(["launchctl", "bootstrap", domain, str(installed_path)], text=True, capture_output=True)
    if result.returncode != 0:
        raise SystemExit(f"launchctl bootstrap failed for {label}: {result.stderr.strip()}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Set up automatic mounted-folder image review.")
    parser.add_argument("folder_name", nargs="?", help="Mounted folder name, for example 图片.")
    parser.add_argument("--folder-name", dest="folder_name_option", help="Mounted folder name.")
    parser.add_argument("--watch-dir", help="Exact mounted folder path, if already known.")
    parser.add_argument("--agent", help="OpenClaw agent id. Defaults to the configured default agent.")
    parser.add_argument("--openclaw", help="Absolute OpenClaw binary path.")
    parser.add_argument("--poll-seconds", type=int, default=30)
    parser.add_argument("--settle-seconds", type=int, default=60)
    parser.add_argument("--max-depth", type=int, default=4)
    parser.add_argument("--install-launch-agent", action="store_true")
    parser.add_argument("--start", action="store_true", help="Start LaunchAgent after installation.")
    parser.add_argument("--baseline", action="store_true", help="Record existing images as already known.")
    parser.add_argument("--dry-run", action="store_true", help="Print plan without writing files.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    folder_name = args.folder_name_option or args.folder_name
    watch_dir = resolve_watch_dir(folder_name, args.watch_dir, args.max_depth)
    openclaw = find_openclaw(args.openclaw)
    requested_agent = args.agent or os.environ.get("OPENCLAW_AGENT_ID") or os.environ.get("OPENCLAW_AGENT")
    agent = choose_agent(load_agents(openclaw), requested_agent)
    agent_id = str(agent.get("id") or agent.get("name") or "main")
    agent_workspace = Path(str(agent.get("workspace") or Path.home() / ".openclaw" / f"workspace-{agent_id}")).expanduser()

    config = build_config(
        watch_dir=watch_dir,
        openclaw=openclaw,
        agent_id=agent_id,
        agent_workspace=agent_workspace,
        poll_seconds=args.poll_seconds,
        settle_seconds=args.settle_seconds,
    )
    root = watcher_root(agent_id)
    config_path = root / "config.json"
    label = f"ai.image-compliance-review.{safe_id(agent_id)}"
    plist_path = root / f"{label}.plist"
    plist_payload = build_plist(label, config_path, agent_id)

    plan = {
        "agent_id": agent_id,
        "agent_workspace": str(agent_workspace),
        "watch_dir": str(watch_dir),
        "config_path": str(config_path),
        "launch_agent_plist": str(plist_path),
        "report_output_root": config["output_root"],
        "install_launch_agent": args.install_launch_agent,
        "start": args.start,
        "baseline": args.baseline,
    }
    print(json.dumps(plan, ensure_ascii=False, indent=2))

    if args.dry_run:
        return 0

    json_dump(config_path, config)
    write_plist(plist_path, plist_payload)

    if args.baseline:
        rc = run_watcher(["--project-dir", str(skill_dir()), "--config", str(config_path), "--baseline"])
        if rc != 0:
            return rc

    if args.install_launch_agent:
        install_launch_agent(plist_path, label, start=args.start)

    return 0


if __name__ == "__main__":
    sys.exit(main())
