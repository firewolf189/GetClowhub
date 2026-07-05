#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Watch a mounted NAS image folder and trigger an image review command.

This watcher intentionally uses polling instead of relying on filesystem events.
SMB/NAS mounts can miss native file notifications, while polling works anywhere
the folder is visible as a normal local path.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".bmp",
    ".gif",
    ".tif",
    ".tiff",
}

DEFAULT_CONFIG = {
    "watch_dir": "",
    "state_file": ".image-review-watcher/state.json",
    "batch_dir": ".image-review-watcher/batches",
    "batch_input_dir": ".image-review-watcher/batch-inputs",
    "log_file": ".image-review-watcher/watcher.log",
    "output_root": "review-output",
    "cleanup_batch_input": "on_success",
    "poll_seconds": 30,
    "settle_seconds": 60,
    "batch_limit": 8,
    "ignore_dir_names": [
        ".image-review-watcher",
        "review-output",
        "review_reports",
        "__MACOSX",
    ],
    "trigger": {
        "enabled": True,
        "cwd": "{project_dir}",
        "command": [
            "openclaw",
            "agent",
            "--agent",
            "main",
            "--timeout",
            "1800",
            "--session-id",
            "image-review-{batch_id}",
            "--json",
            "--message",
            (
                "请使用 image-compliance-review 技能审核新增图片。"
                "项目目录：{project_dir}。"
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


@dataclass(frozen=True)
class SeenFile:
    path: str
    size: int
    mtime_ns: int

    @property
    def signature(self) -> str:
        return f"{self.size}:{self.mtime_ns}"


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json_atomic(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    tmp_path.replace(path)


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def resolve_path(project_dir: Path, value: str) -> Path:
    formatted = value.format(project_dir=project_dir)
    path = Path(formatted).expanduser()
    if not path.is_absolute():
        path = project_dir / path
    return path


def log_line(log_file: Path, message: str) -> None:
    line = f"[{now_iso()}] {message}"
    print(line, flush=True)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    with log_file.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def is_image_file(path: Path) -> bool:
    if path.name.startswith(".") or path.name.lower() == "thumbs.db":
        return False
    return path.suffix.lower() in IMAGE_EXTENSIONS


def under_ignored_dir(path: Path, root: Path, ignored_names: set[str]) -> bool:
    try:
        rel_parts = path.relative_to(root).parts
    except ValueError:
        return False
    return any(part in ignored_names for part in rel_parts[:-1])


def scan_images(root: Path, ignored_names: set[str]) -> list[SeenFile]:
    images: list[SeenFile] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if under_ignored_dir(path, root, ignored_names):
            continue
        if not is_image_file(path):
            continue
        stat = path.stat()
        images.append(
            SeenFile(
                path=str(path),
                size=stat.st_size,
                mtime_ns=stat.st_mtime_ns,
            )
        )
    return sorted(images, key=lambda item: item.path)


def update_pending(
    state: dict[str, Any],
    scanned: list[SeenFile],
    current_time: float,
) -> None:
    pending = state.setdefault("pending", {})
    processed = state.setdefault("processed", {})
    current_paths = {item.path for item in scanned}

    for stale_path in list(pending):
        if stale_path not in current_paths:
            del pending[stale_path]

    for item in scanned:
        processed_signature = processed.get(item.path, {}).get("signature")
        if processed_signature == item.signature:
            continue

        pending_item = pending.get(item.path)
        if pending_item and pending_item.get("signature") == item.signature:
            continue

        pending[item.path] = {
            "signature": item.signature,
            "size": item.size,
            "mtime_ns": item.mtime_ns,
            "first_seen_at": current_time,
            "last_changed_at": current_time,
        }


def ready_paths(
    state: dict[str, Any],
    current_time: float,
    settle_seconds: int,
    batch_limit: int,
) -> list[str]:
    pending = state.setdefault("pending", {})
    ready = [
        path
        for path, item in pending.items()
        if current_time - float(item.get("last_changed_at", current_time)) >= settle_seconds
    ]
    return sorted(ready)[:batch_limit]


def format_value(value: str, variables: dict[str, str]) -> str:
    return value.format(**variables)


def build_command(command: list[str], variables: dict[str, str]) -> list[str]:
    return [format_value(part, variables) for part in command]


def shell_preview(command: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in command)


def prepare_batch_input(
    batch_input_root: Path,
    watch_dir: Path,
    paths: list[str],
    batch_id: str,
) -> Path:
    batch_input_dir = batch_input_root / batch_id
    if batch_input_dir.exists():
        shutil.rmtree(batch_input_dir)
    for path in paths:
        source = Path(path)
        relative = source.relative_to(watch_dir)
        destination = batch_input_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    return batch_input_dir


def make_batch_file(
    batch_dir: Path,
    watch_dir: Path,
    batch_input_dir: Path,
    run_output_dir: Path,
    batch_report_file: Path,
    paths: list[str],
    batch_id: str,
) -> Path:
    batch_file = batch_dir / f"{batch_id}.json"
    payload = {
        "batch_id": batch_id,
        "created_at": now_iso(),
        "watch_dir": str(watch_dir),
        "batch_input_dir": str(batch_input_dir),
        "run_output_dir": str(run_output_dir),
        "batch_report_file": str(batch_report_file),
        "review_results_file": str(run_output_dir / "review_results.json"),
        "images": [
            {
                "source_path": path,
                "path": str(batch_input_dir / os.path.relpath(path, str(watch_dir))),
                "relative_path": os.path.relpath(path, str(watch_dir)),
            }
            for path in paths
        ],
    }
    write_json_atomic(batch_file, payload)
    return batch_file


def report_path_for_batch(output_root: Path, batch_id: str) -> Path:
    try:
        report_date = datetime.strptime(batch_id[:8], "%Y%m%d").date().isoformat()
    except ValueError:
        report_date = datetime.now().date().isoformat()
    return output_root / "stats" / f"{report_date}.md"


def run_trigger(
    config: dict[str, Any],
    project_dir: Path,
    watch_dir: Path,
    batch_file: Path,
    run_output_dir: Path,
    batch_report_file: Path,
    log_file: Path,
    dry_run: bool,
) -> bool:
    trigger = config.get("trigger", {})
    if not trigger.get("enabled", True):
        log_line(log_file, "Trigger is disabled; batch recorded only.")
        return True

    variables = {
        "project_dir": str(project_dir),
        "watch_dir": str(watch_dir),
        "batch_file": str(batch_file),
        "batch_id": batch_file.stem,
        "batch_input_dir": os.environ.get("IMAGE_REVIEW_BATCH_INPUT_DIR", ""),
        "run_output_dir": str(run_output_dir),
        "batch_report_file": str(batch_report_file),
        "review_results_file": str(run_output_dir / "review_results.json"),
        "rules_file": str(project_dir / "rules.md"),
        "agent_workspace": str(config.get("agent_workspace") or ""),
    }
    command = build_command(trigger["command"], variables)
    cwd = Path(format_value(trigger.get("cwd", "{project_dir}"), variables))
    env = os.environ.copy()
    env.update(
        {
            "IMAGE_REVIEW_PROJECT_DIR": str(project_dir),
            "IMAGE_REVIEW_WATCH_DIR": str(watch_dir),
            "IMAGE_REVIEW_BATCH_FILE": str(batch_file),
            "IMAGE_REVIEW_BATCH_INPUT_DIR": variables["batch_input_dir"],
            "IMAGE_REVIEW_OUTPUT_DIR": str(run_output_dir),
            "IMAGE_REVIEW_RULES_FILE": str(project_dir / "rules.md"),
        }
    )

    log_line(log_file, f"Trigger command: {shell_preview(command)}")
    if dry_run:
        log_line(log_file, "Dry run enabled; command was not executed.")
        return True

    run_output_dir.mkdir(parents=True, exist_ok=True)
    batch_report_file.parent.mkdir(parents=True, exist_ok=True)
    previous_report_mtime = batch_report_file.stat().st_mtime_ns if batch_report_file.exists() else None
    process = subprocess.Popen(
        command,
        cwd=str(cwd),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
    )
    if process.stdout:
        for line in process.stdout:
            line = line.rstrip()
            if line:
                log_line(log_file, f"Trigger output: {line}")

    returncode = process.wait()
    if returncode != 0:
        log_line(log_file, f"Trigger failed with exit code {returncode}.")
        return False

    if not batch_report_file.exists():
        log_line(log_file, f"Trigger returned success but batch report was not found: {batch_report_file}")
        return False
    current_report_mtime = batch_report_file.stat().st_mtime_ns
    if previous_report_mtime is not None and current_report_mtime == previous_report_mtime:
        log_line(log_file, f"Trigger returned success but batch report was not updated: {batch_report_file}")
        return False
    review_results_file = run_output_dir / "review_results.json"
    if not review_results_file.exists():
        log_line(log_file, f"Trigger returned success but review JSON was not found: {review_results_file}")
        return False

    log_line(log_file, f"Trigger completed successfully: {batch_report_file}")
    return True


def process_ready_batch(
    config: dict[str, Any],
    project_dir: Path,
    watch_dir: Path,
    state: dict[str, Any],
    paths: list[str],
    dry_run: bool,
) -> bool:
    batch_dir = resolve_path(project_dir, config["batch_dir"])
    batch_input_root = resolve_path(project_dir, config["batch_input_dir"])
    log_file = resolve_path(project_dir, config["log_file"])
    output_root = resolve_path(project_dir, config["output_root"])
    batch_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    run_output_dir = output_root / batch_id
    batch_report_file = report_path_for_batch(output_root, batch_id)
    batch_input_dir = prepare_batch_input(batch_input_root, watch_dir, paths, batch_id)
    batch_file = make_batch_file(batch_dir, watch_dir, batch_input_dir, run_output_dir, batch_report_file, paths, batch_id)
    log_line(log_file, f"Ready batch: {len(paths)} image(s), manifest {batch_file}")
    log_line(log_file, f"Batch input dir: {batch_input_dir}")
    log_line(log_file, f"Batch report file: {batch_report_file}")

    previous_batch_input_dir = os.environ.get("IMAGE_REVIEW_BATCH_INPUT_DIR")
    os.environ["IMAGE_REVIEW_BATCH_INPUT_DIR"] = str(batch_input_dir)
    success = run_trigger(
        config=config,
        project_dir=project_dir,
        watch_dir=watch_dir,
        batch_file=batch_file,
        run_output_dir=run_output_dir,
        batch_report_file=batch_report_file,
        log_file=log_file,
        dry_run=dry_run,
    )
    if previous_batch_input_dir is None:
        os.environ.pop("IMAGE_REVIEW_BATCH_INPUT_DIR", None)
    else:
        os.environ["IMAGE_REVIEW_BATCH_INPUT_DIR"] = previous_batch_input_dir
    if not success:
        return False
    if dry_run:
        log_line(log_file, "Dry run complete; pending files were not marked processed.")
        return True

    if config.get("cleanup_batch_input", "on_success") == "on_success":
        shutil.rmtree(batch_input_dir, ignore_errors=True)
        log_line(log_file, f"Cleaned batch input dir: {batch_input_dir}")

    pending = state.setdefault("pending", {})
    processed = state.setdefault("processed", {})
    for path in paths:
        item = pending.pop(path, None)
        if item:
            processed[path] = {
                "signature": item["signature"],
                "processed_at": time.time(),
                "batch_file": str(batch_file),
                "run_output_dir": str(run_output_dir),
            }
    state["last_success_at"] = time.time()
    return True


def run_once(config: dict[str, Any], project_dir: Path, dry_run: bool) -> None:
    if not str(config.get("watch_dir") or "").strip():
        raise SystemExit("watch_dir is not configured. Run setup_nas_watcher.py first.")
    watch_dir = resolve_path(project_dir, config["watch_dir"])
    state_file = resolve_path(project_dir, config["state_file"])
    log_file = resolve_path(project_dir, config["log_file"])
    state = load_json(state_file, {"pending": {}, "processed": {}})

    if not watch_dir.exists():
        log_line(log_file, f"Watch dir is not mounted or does not exist: {watch_dir}")
        write_json_atomic(state_file, state)
        return

    scanned = scan_images(watch_dir, set(config.get("ignore_dir_names", [])))
    current_time = time.time()
    update_pending(state, scanned, current_time)
    paths = ready_paths(
        state,
        current_time,
        int(config["settle_seconds"]),
        int(config["batch_limit"]),
    )
    log_line(log_file, f"Scanned {len(scanned)} image(s); ready {len(paths)}.")
    if paths:
        process_ready_batch(config, project_dir, watch_dir, state, paths, dry_run=dry_run)
    write_json_atomic(state_file, state)


def baseline_current_files(config: dict[str, Any], project_dir: Path) -> None:
    if not str(config.get("watch_dir") or "").strip():
        raise SystemExit("watch_dir is not configured. Run setup_nas_watcher.py first.")
    watch_dir = resolve_path(project_dir, config["watch_dir"])
    state_file = resolve_path(project_dir, config["state_file"])
    log_file = resolve_path(project_dir, config["log_file"])
    state = load_json(state_file, {"pending": {}, "processed": {}})

    if not watch_dir.exists():
        log_line(log_file, f"Cannot baseline missing watch dir: {watch_dir}")
        write_json_atomic(state_file, state)
        return

    scanned = scan_images(watch_dir, set(config.get("ignore_dir_names", [])))
    processed = state.setdefault("processed", {})
    for item in scanned:
        processed[item.path] = {
            "signature": item.signature,
            "processed_at": time.time(),
            "baseline": True,
        }
    state["pending"] = {}
    state["last_baseline_at"] = time.time()
    write_json_atomic(state_file, state)
    log_line(log_file, f"Baseline recorded {len(scanned)} existing image(s).")


def load_config(config_path: Path) -> dict[str, Any]:
    if not config_path.exists():
        return DEFAULT_CONFIG
    user_config = load_json(config_path, {})
    return deep_merge(DEFAULT_CONFIG, user_config)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Poll a mounted NAS image folder and trigger OpenClaw/Codex review.",
    )
    parser.add_argument(
        "--config",
        default="config/nas-image-watcher.json",
        help="JSON config path, relative to project dir by default.",
    )
    parser.add_argument(
        "--project-dir",
        default=None,
        help="Project directory containing rules.md and watcher config. Defaults to current directory.",
    )
    parser.add_argument("--once", action="store_true", help="Scan once and exit.")
    parser.add_argument(
        "--baseline",
        action="store_true",
        help="Record current images as already known, without triggering review.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Do not run trigger command.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    project_dir = Path(
        args.project_dir or os.environ.get("IMAGE_REVIEW_PROJECT_DIR") or Path.cwd()
    ).expanduser().resolve()
    config_path = Path(args.config).expanduser()
    if not config_path.is_absolute():
        config_path = project_dir / config_path
    config = load_config(config_path)
    log_file = resolve_path(project_dir, config["log_file"])

    if args.baseline:
        baseline_current_files(config, project_dir)
        return 0

    if args.once:
        run_once(config, project_dir, dry_run=args.dry_run)
        return 0

    log_line(log_file, f"Watcher started with config: {config_path}")
    while True:
        try:
            config = load_config(config_path)
            log_file = resolve_path(project_dir, config["log_file"])
            run_once(config, project_dir, dry_run=args.dry_run)
        except KeyboardInterrupt:
            log_line(log_file, "Watcher stopped by keyboard interrupt.")
            return 130
        except Exception as exc:  # noqa: BLE001 - keep daemon alive and log failures.
            log_line(log_file, f"Watcher error: {exc!r}")
        time.sleep(int(config["poll_seconds"]))


if __name__ == "__main__":
    sys.exit(main())
