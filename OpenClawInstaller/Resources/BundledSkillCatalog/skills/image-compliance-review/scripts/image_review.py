#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CLI for current-model image compliance review."""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tif", ".tiff"}
RULE_LABELS = {
    "logo": "Logo规范",
    "copy": "文案规范",
    "market": "市场雷区",
    "other": "其他问题",
}
MANUAL_REVIEW_STATUSES = {
    "manual_review",
    "needs_review",
    "need_review",
    "review_required",
    "human_review",
    "需人工复核",
}


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def is_image_file(path: Path) -> bool:
    if not path.is_file():
        return False
    if path.name.startswith(".") or path.name.lower() == "thumbs.db":
        return False
    return path.suffix.lower() in IMAGE_EXTENSIONS


def discover_images(root: Path, exclude_dirs: Optional[Sequence[Path]] = None) -> List[Path]:
    exclude_resolved = [p.resolve() for p in (exclude_dirs or []) if p.exists()]
    if root.is_file():
        return [root] if is_image_file(root) else []

    images: List[Path] = []
    for path in sorted(root.rglob("*")):
        if not is_image_file(path):
            continue
        resolved = path.resolve()
        if any(is_relative_to(resolved, excluded) for excluded in exclude_resolved):
            continue
        images.append(path)
    return images


def person_for_image(image_path: Path, input_root: Path) -> str:
    if input_root.is_file():
        return image_path.parent.name or "未分组"

    rel = image_path.relative_to(input_root)
    if len(rel.parts) > 1:
        return rel.parts[0]
    return input_root.name or "未分组"


def group_images(images: Sequence[Path], input_root: Path) -> Dict[str, List[Path]]:
    grouped: Dict[str, List[Path]] = {}
    for image in images:
        grouped.setdefault(person_for_image(image, input_root), []).append(image)
    return grouped


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text()


def json_dumps(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def to_posix(path: Path) -> str:
    return path.as_posix()


def relative_path(path: Optional[str], base_dir: Path) -> str:
    if not path:
        return ""
    path_obj = Path(path)
    try:
        return os.path.relpath(str(path_obj), str(base_dir))
    except ValueError:
        return str(path_obj)


def rule_label(rule_id: Any) -> str:
    normalized = str(rule_id or "other").strip().lower()
    return RULE_LABELS.get(normalized, str(rule_id or "其他问题"))


def normalized_status(value: Any) -> str:
    return str(value or "").strip().lower().replace("-", "_")


def is_manual_review(result: Dict[str, Any]) -> bool:
    status = normalized_status(result.get("status"))
    summary = str(result.get("summary") or "").strip()
    if status in MANUAL_REVIEW_STATUSES:
        return True
    return "人工复核" in summary or "manual review" in summary.lower()


def result_label(result: Dict[str, Any]) -> str:
    if normalized_status(result.get("status")) == "error":
        return "审核错误"
    if result.get("is_pass"):
        return "合格"
    if is_manual_review(result):
        return "需人工复核"
    return "不合格"


def empty_person_summary() -> Dict[str, Any]:
    return {
        "total": 0,
        "passed": 0,
        "failed": 0,
        "manual_review": 0,
        "errors": 0,
        "issue_count": 0,
        "images": [],
    }


def add_result_to_summary(summary: Dict[str, Any], result: Dict[str, Any]) -> None:
    summary["total"] += 1
    summary.setdefault("images", []).append(result)
    status = normalized_status(result.get("status"))
    if status == "error":
        summary["errors"] += 1
        return
    if result.get("is_pass"):
        summary["passed"] += 1
        return
    if is_manual_review(result):
        summary["manual_review"] += 1
    else:
        summary["failed"] += 1
    summary["issue_count"] += len(result.get("issues", []))


def finalize_person_summary(summary: Dict[str, Any]) -> None:
    reviewed = summary["passed"] + summary["failed"] + summary["manual_review"]
    summary["pass_rate"] = round(summary["passed"] / reviewed * 100, 2) if reviewed else 0.0


def summarize_people(results: Sequence[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    people: Dict[str, Dict[str, Any]] = {}
    for result in results:
        person = result["person"]
        summary = people.setdefault(person, empty_person_summary())
        add_result_to_summary(summary, result)

    for summary in people.values():
        finalize_person_summary(summary)
    return people


def build_payload(
    input_root: Path,
    rules_path: Path,
    output_dir: Path,
    model_label: str,
    results: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    people = summarize_people(results)
    total = sum(item["total"] for item in people.values())
    passed = sum(item["passed"] for item in people.values())
    failed = sum(item["failed"] for item in people.values())
    manual_review = sum(item["manual_review"] for item in people.values())
    errors = sum(item["errors"] for item in people.values())
    issue_count = sum(item["issue_count"] for item in people.values())
    reviewed = passed + failed + manual_review

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "input_dir": to_posix(input_root.resolve()),
        "rules_file": to_posix(rules_path.resolve()),
        "output_dir": to_posix(output_dir.resolve()),
        "batch_id": output_dir.name,
        "model_label": model_label,
        "summary": {
            "total_images": total,
            "reviewed_images": reviewed,
            "passed_images": passed,
            "failed_images": failed,
            "manual_review_images": manual_review,
            "error_images": errors,
            "issue_count": issue_count,
            "pass_rate": round(passed / reviewed * 100, 2) if reviewed else 0.0,
        },
        "people": people,
    }


def format_generated_time(value: Any) -> str:
    if not value:
        return ""
    text = str(value)
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return str(value)
    return parsed.astimezone().strftime("%Y-%m-%d %H:%M")


def render_markdown(payload: Dict[str, Any], report_dir: Path) -> str:
    summary = payload["summary"]
    lines = [
        "# 单批图片审核明细",
        "",
        "批次：{}".format(payload.get("batch_id") or Path(str(payload.get("output_dir", ""))).name or "未命名批次"),
        "审核时间：{}".format(format_generated_time(payload.get("generated_at"))),
        "图片总数：{}".format(summary["total_images"]),
        "合格：{}".format(summary["passed_images"]),
        "不合格：{}".format(summary["failed_images"]),
        "需人工复核：{}".format(summary.get("manual_review_images", 0)),
        "审核错误：{}".format(summary["error_images"]),
        "",
        "## 人员汇总",
        "",
        "| 人名 | 图片数 | 合格 | 不合格 | 需复核 | 合格率 |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]

    people: Dict[str, Dict[str, Any]] = payload["people"]
    for person in sorted(people):
        item = people[person]
        lines.append(
            "| {} | {} | {} | {} | {} | {:.2f}% |".format(
                person,
                item["total"],
                item["passed"],
                item["failed"],
                item.get("manual_review", 0),
                item["pass_rate"],
            )
        )

    lines.extend(["", "## 问题明细", ""])
    has_problem_detail = False
    for person in sorted(people):
        problem_images = [
            image
            for image in people[person]["images"]
            if normalized_status(image.get("status")) == "error" or not image.get("is_pass")
        ]
        if not problem_images:
            continue

        has_problem_detail = True
        lines.append("### {}".format(person))
        lines.append("")
        for image in problem_images:
            lines.append("图片：{}".format(image["image_name"]))
            lines.append("结果：{}".format(result_label(image)))
            if normalized_status(image.get("status")) == "error":
                lines.append("问题：")
                lines.append("1. 审核错误：{}".format(image.get("error") or "未知错误"))
                lines.append("   修改方案：请人工复核该图片，并补充审核结论。")
                lines.append("")
                continue

            issues = image.get("issues", [])
            if issues:
                lines.append("问题：")
                for index, issue in enumerate(issues, start=1):
                    evidence = issue.get("evidence")
                    description = issue.get("description") or ""
                    if evidence and evidence not in description:
                        description = "{}；证据：{}".format(description, evidence)
                    lines.append("{}. {}：{}".format(index, rule_label(issue.get("rule_id")), description))
                    lines.append("   修改方案：{}".format(issue.get("suggestion") or "请按规则调整。"))
            else:
                lines.append("问题：未提供具体问题。")
                lines.append("修改方案：请人工复核该图片，并补充具体修改方案。")
            lines.append("")

    if not has_problem_detail:
        lines.append("本批未发现不合格或需人工复核图片。")
        lines.append("")

    return "\n".join(lines)


def count_command(args: argparse.Namespace) -> int:
    input_root = Path(args.input)
    images = discover_images(input_root)
    grouped = group_images(images, input_root)
    total = sum(len(paths) for paths in grouped.values())

    if args.json:
        payload = {
            "input_dir": to_posix(input_root.resolve()),
            "total_images": total,
            "people": {person: len(paths) for person, paths in sorted(grouped.items())},
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    print("| 人名 | 图片数量 |")
    print("| --- | ---: |")
    for person in sorted(grouped):
        print("| {} | {} |".format(person, len(grouped[person])))
    print("| 总计 | {} |".format(total))
    return 0


def coerce_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "yes", "y", "1", "pass", "passed", "ok", "合格", "通过"}:
            return True
        if normalized in {"false", "no", "n", "0", "fail", "failed", "不合格", "未通过"}:
            return False
    return default


def normalize_issue(raw_issue: Dict[str, Any]) -> Dict[str, Any]:
    description = str(raw_issue.get("description") or raw_issue.get("error") or "").strip()
    suggestion = str(raw_issue.get("suggestion") or raw_issue.get("fix") or "").strip()
    evidence = str(raw_issue.get("evidence") or "").strip()
    if not description and evidence:
        description = evidence
    return {
        "rule_id": str(raw_issue.get("rule_id") or raw_issue.get("rule") or "other"),
        "description": description or "未提供具体错误元素。",
        "evidence": evidence,
        "suggestion": suggestion or "请根据审核规范调整该问题点。",
    }


def normalize_draft_issues(raw_issues: Any) -> List[Dict[str, Any]]:
    if not isinstance(raw_issues, list):
        return []
    return [normalize_issue(issue) for issue in raw_issues if isinstance(issue, dict)]


def find_image_from_draft(
    raw: Dict[str, Any],
    input_root: Path,
    images_by_resolved: Dict[str, Path],
    images_by_relative: Dict[str, Path],
    images_by_name: Dict[str, List[Path]],
) -> Optional[Path]:
    candidates = [
        raw.get("image_path"),
        raw.get("path"),
        raw.get("relative_path"),
        raw.get("image"),
        raw.get("filename"),
        raw.get("image_name"),
    ]
    for candidate in candidates:
        if not candidate:
            continue
        candidate_path = Path(str(candidate))
        possible_paths = []
        if candidate_path.is_absolute():
            possible_paths.append(candidate_path)
        else:
            possible_paths.append(candidate_path)
            possible_paths.append(input_root / candidate_path)

        for possible_path in possible_paths:
            resolved = str(possible_path.resolve()) if possible_path.exists() else str(possible_path)
            if resolved in images_by_resolved:
                return images_by_resolved[resolved]

        normalized = to_posix(candidate_path)
        if normalized in images_by_relative:
            return images_by_relative[normalized]
        if candidate_path.name in images_by_name and len(images_by_name[candidate_path.name]) == 1:
            return images_by_name[candidate_path.name][0]
    return None


def draft_results_from_json(path: Path) -> List[Dict[str, Any]]:
    payload = json.loads(read_text(path))
    if isinstance(payload, list):
        raw_results = payload
    elif isinstance(payload, dict):
        raw_results = payload.get("results") or payload.get("images") or []
    else:
        raw_results = []

    if not isinstance(raw_results, list):
        raise SystemExit("Draft JSON must contain a list or an object with a results list.")
    return [item for item in raw_results if isinstance(item, dict)]


def parse_date_arg(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise SystemExit("Date must use YYYY-MM-DD format: {}".format(value)) from exc


def payload_date(payload: Dict[str, Any], path: Optional[Path] = None) -> Optional[date]:
    generated_at = payload.get("generated_at")
    if generated_at:
        text = str(generated_at)
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        try:
            return datetime.fromisoformat(text).date()
        except ValueError:
            pass

    if path:
        for candidate in (path.parent.name, path.stem):
            normalized = candidate[:10]
            if len(normalized) == 10:
                try:
                    return date.fromisoformat(normalized)
                except ValueError:
                    pass
            compact = candidate[:8]
            if len(compact) == 8 and compact.isdigit():
                try:
                    return date(int(compact[:4]), int(compact[4:6]), int(compact[6:8]))
                except ValueError:
                    pass
    return None


def load_result_payloads(results_root: Path) -> List[Dict[str, Any]]:
    payloads: List[Dict[str, Any]] = []
    for path in sorted(results_root.rglob("review_results.json")):
        try:
            payload = json.loads(read_text(path))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(payload, dict):
            payload["_source_path"] = str(path)
            payloads.append(payload)
    return payloads


def iter_payload_images(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    images: List[Dict[str, Any]] = []
    people = payload.get("people", {})
    if isinstance(people, dict):
        for person, item in people.items():
            if not isinstance(item, dict):
                continue
            for image in item.get("images", []):
                if not isinstance(image, dict):
                    continue
                copied = dict(image)
                copied.setdefault("person", str(person))
                images.append(copied)
    return images


def build_period_stats(
    payloads: Sequence[Dict[str, Any]],
    since: date,
    until: date,
) -> Dict[str, Any]:
    people: Dict[str, Dict[str, Any]] = {}
    included_batches = 0
    skipped_without_date = 0

    for payload in payloads:
        source_path = Path(str(payload.get("_source_path", ""))) if payload.get("_source_path") else None
        current_date = payload_date(payload, source_path)
        if current_date is None:
            skipped_without_date += 1
            continue
        if current_date < since or current_date > until:
            continue

        included_batches += 1
        for image in iter_payload_images(payload):
            person = str(image.get("person") or "未分组")
            summary = people.setdefault(person, empty_person_summary())
            add_result_to_summary(summary, image)

    for summary in people.values():
        finalize_person_summary(summary)

    total = sum(item["total"] for item in people.values())
    passed = sum(item["passed"] for item in people.values())
    failed = sum(item["failed"] for item in people.values())
    manual_review = sum(item["manual_review"] for item in people.values())
    errors = sum(item["errors"] for item in people.values())
    issue_count = sum(item["issue_count"] for item in people.values())
    reviewed = passed + failed + manual_review

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "since": since.isoformat(),
        "until": until.isoformat(),
        "summary": {
            "batch_count": included_batches,
            "skipped_without_date": skipped_without_date,
            "total_images": total,
            "reviewed_images": reviewed,
            "passed_images": passed,
            "failed_images": failed,
            "manual_review_images": manual_review,
            "error_images": errors,
            "issue_count": issue_count,
            "pass_rate": round(passed / reviewed * 100, 2) if reviewed else 0.0,
        },
        "people": people,
    }


def build_period_stats_from_root(results_root: Path, since: date, until: date) -> Dict[str, Any]:
    return build_period_stats(load_result_payloads(results_root), since=since, until=until)


def render_period_stats_markdown(stats: Dict[str, Any]) -> str:
    summary = stats["summary"]
    lines = [
        "# 图片审核合格率统计",
        "",
        "统计周期：{} 至 {}".format(stats["since"], stats["until"]),
        "统计批次：{}".format(summary["batch_count"]),
        "图片总数：{}".format(summary["total_images"]),
        "合格：{}".format(summary["passed_images"]),
        "不合格：{}".format(summary["failed_images"]),
        "需人工复核：{}".format(summary["manual_review_images"]),
        "审核错误：{}".format(summary["error_images"]),
        "总合格率：{:.2f}%".format(summary["pass_rate"]),
        "",
        "| 人名 | 图片总数 | 合格 | 不合格 | 需复核 | 审核错误 | 问题数 | 合格率 |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]

    people: Dict[str, Dict[str, Any]] = stats["people"]
    for person in sorted(people):
        item = people[person]
        lines.append(
            "| {} | {} | {} | {} | {} | {} | {} | {:.2f}% |".format(
                person,
                item["total"],
                item["passed"],
                item["failed"],
                item.get("manual_review", 0),
                item["errors"],
                item["issue_count"],
                item["pass_rate"],
            )
        )

    if not people:
        lines.append("| 无数据 | 0 | 0 | 0 | 0 | 0 | 0 | 0.00% |")

    lines.append("")
    return "\n".join(lines)


def finalize_command(args: argparse.Namespace) -> int:
    draft_path = Path(args.draft_json)
    input_root = Path(args.input)
    rules_path = Path(args.rules)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if not draft_path.exists():
        raise SystemExit("Draft JSON not found: {}".format(draft_path))
    if not input_root.exists():
        raise SystemExit("Input path not found: {}".format(input_root))
    if not rules_path.exists():
        raise SystemExit("Rules file not found: {}".format(rules_path))

    images = discover_images(input_root, exclude_dirs=[output_dir])
    images_by_resolved = {str(path.resolve()): path for path in images}
    images_by_relative = {
        to_posix(path.relative_to(input_root) if not input_root.is_file() else Path(path.name)): path
        for path in images
    }
    images_by_name: Dict[str, List[Path]] = {}
    for image_path in images:
        images_by_name.setdefault(image_path.name, []).append(image_path)

    results: List[Dict[str, Any]] = []
    seen: set = set()
    for raw in draft_results_from_json(draft_path):
        image_path = find_image_from_draft(raw, input_root, images_by_resolved, images_by_relative, images_by_name)
        if image_path is None:
            results.append(
                {
                    "person": str(raw.get("person") or "未匹配"),
                    "image_name": str(raw.get("image_name") or raw.get("image_path") or "未知图片"),
                    "path": "",
                    "relative_path": "",
                    "status": "error",
                    "is_pass": False,
                    "summary": "草稿中的图片未在输入目录中找到",
                    "issues": [],
                    "error": "Image path in draft was not found under input folder.",
                }
            )
            continue

        resolved_key = str(image_path.resolve())
        seen.add(resolved_key)
        person = str(raw.get("person") or person_for_image(image_path, input_root))
        rel_path = image_path.relative_to(input_root) if not input_root.is_file() else Path(image_path.name)
        issues = normalize_draft_issues(raw.get("issues", []))
        is_pass = coerce_bool(raw.get("is_pass", raw.get("pass", None)), default=(len(issues) == 0))
        if issues:
            is_pass = False
        if not is_pass and not issues:
            issues.append(
                {
                    "rule_id": "other",
                    "description": str(raw.get("summary") or "当前模型判定不合格，但草稿未列出具体问题。"),
                    "evidence": "",
                    "suggestion": "请人工复核该图片，并补充具体修改方案。",
                }
            )

        result = {
            "person": person,
            "image_name": image_path.name,
            "path": to_posix(image_path.resolve()),
            "relative_path": to_posix(rel_path),
            "status": str(raw.get("status") or "reviewed"),
            "is_pass": is_pass,
            "summary": str(raw.get("summary") or ("合格" if is_pass else "不合格")),
            "issues": issues,
        }
        results.append(result)

    for image_path in images:
        resolved_key = str(image_path.resolve())
        if resolved_key in seen:
            continue
        person = person_for_image(image_path, input_root)
        rel_path = image_path.relative_to(input_root) if not input_root.is_file() else Path(image_path.name)
        if args.assume_missing_pass:
            status = "reviewed"
            is_pass = True
            summary = "草稿未列出该图片，按合格处理"
            error = None
        else:
            status = "error"
            is_pass = False
            summary = "草稿缺少该图片的审核结果"
            error = "Missing review result in draft JSON."
        item = {
            "person": person,
            "image_name": image_path.name,
            "path": to_posix(image_path.resolve()),
            "relative_path": to_posix(rel_path),
            "status": status,
            "is_pass": is_pass,
            "summary": summary,
            "issues": [],
        }
        if error:
            item["error"] = error
        results.append(item)

    payload = build_payload(
        input_root=input_root,
        rules_path=rules_path,
        output_dir=output_dir,
        model_label=args.model_label,
        results=results,
    )

    report_path = Path(args.report_output) if args.report_output else output_dir / args.report_name
    report_path.parent.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / args.json_name
    json_path.write_text(json_dumps(payload), encoding="utf-8")
    report_path.write_text(render_markdown(payload, report_path.parent), encoding="utf-8")

    summary = payload["summary"]
    print("完成：总数 {}，不合格 {}，合格率 {:.2f}%".format(
        summary["total_images"], summary["failed_images"], summary["pass_rate"]
    ))
    print("JSON：{}".format(json_path))
    print("报告：{}".format(report_path))
    return 0


def report_command(args: argparse.Namespace) -> int:
    json_path = Path(args.json_result)
    payload = json.loads(read_text(json_path))
    output_path = Path(args.output) if args.output else json_path.with_name("batch_review.md")
    output_path.write_text(render_markdown(payload, output_path.parent), encoding="utf-8")
    print("报告：{}".format(output_path))
    return 0


def stats_command(args: argparse.Namespace) -> int:
    results_root = Path(args.results_root)
    since = parse_date_arg(args.since)
    until = parse_date_arg(args.until)
    if until < since:
        raise SystemExit("--until must be on or after --since")
    stats = build_period_stats_from_root(results_root, since=since, until=until)
    output_path = Path(args.output) if args.output else results_root / "stats" / "{}_{}.md".format(since, until)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(render_period_stats_markdown(stats), encoding="utf-8")
    summary = stats["summary"]
    print("统计：{} 至 {}，图片 {}，合格率 {:.2f}%".format(
        since,
        until,
        summary["total_images"],
        summary["pass_rate"],
    ))
    print("统计文件：{}".format(output_path))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Current-model image compliance review CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    count_parser = subparsers.add_parser("count", help="count local images by person")
    count_parser.add_argument("input", help="image folder or image file")
    count_parser.add_argument("--json", action="store_true", help="print JSON instead of Markdown table")
    count_parser.set_defaults(func=count_command)

    finalize_parser = subparsers.add_parser(
        "finalize",
        help="turn current-agent review draft JSON into a Markdown report",
    )
    finalize_parser.add_argument("draft_json", help="draft JSON authored by the current agent/model")
    finalize_parser.add_argument("--input", required=True, help="image folder or image file")
    finalize_parser.add_argument("--rules", default="rules.md", help="Markdown rules file")
    finalize_parser.add_argument("--output-dir", default="review-output", help="output directory")
    finalize_parser.add_argument(
        "--model-label",
        default="current client model",
        help="label shown in the report for the model used by the agent",
    )
    finalize_parser.add_argument(
        "--assume-missing-pass",
        action="store_true",
        help="treat images missing from the draft as passed instead of reporting incomplete review errors",
    )
    finalize_parser.add_argument(
        "--save-json",
        action="store_true",
        help="kept for compatibility; review_results.json is always saved",
    )
    finalize_parser.add_argument("--json-name", default="review_results.json", help="JSON output filename")
    finalize_parser.add_argument("--report-name", default="batch_review.md", help="Markdown output filename")
    finalize_parser.add_argument("--report-output", help="exact Markdown output path")
    finalize_parser.set_defaults(func=finalize_command)

    report_parser = subparsers.add_parser("report", help="render Markdown from review_results.json")
    report_parser.add_argument("json_result", help="review_results.json path")
    report_parser.add_argument("--output", help="Markdown output path")
    report_parser.set_defaults(func=report_command)

    stats_parser = subparsers.add_parser("stats", help="aggregate pass rates from review_results.json files")
    stats_parser.add_argument("--results-root", default="review-output", help="root containing batch review_results.json files")
    stats_parser.add_argument("--since", required=True, help="start date, YYYY-MM-DD")
    stats_parser.add_argument("--until", required=True, help="end date, YYYY-MM-DD")
    stats_parser.add_argument("--output", help="Markdown output path; defaults to review-output/stats/SINCE_UNTIL.md")
    stats_parser.set_defaults(func=stats_command)

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
