---
name: image-compliance-review
description: Use when the current agent/model should review uploaded or local image folders against rules.md, count pass rates, export a per-person Markdown report, or set up automatic NAS/mounted-folder watching for newly uploaded image review.
metadata:
  short-description: Review image folders with the current model and export reports
---

# Image Compliance Review

Use this skill to audit generated image folders against a Markdown rule file with the current agent's vision/model capabilities, set up automatic review for newly uploaded images in a mounted NAS/local folder, or summarize pass rates from prior review JSON files. Do not ask the user to configure model keys, model names, URLs, or external model settings.

The bundled scripts are helpers for deterministic file operations: counting images, normalizing reviewed issue data, exporting Markdown, aggregating pass-rate statistics, and optionally watching a mounted NAS folder for newly uploaded images. The compliance judgment itself is always made by the current agent/model.

## Default Workflow

1. Read the project rule file, usually `rules.md` (already included in this skill directory).
2. Treat the uploaded folder or local image folder as the data source. The expected layout is usually `<图片目录>/<人名>/<图片文件>`.
3. Count images with the helper script.
4. Review each image using the current agent/model's image understanding. Do not ask the user to provide a separate model key.
   - Keep vision batches small: inspect at most 8 images before recording structured results.
   - If a folder contains more than 8 images, split the work by person or filename order into 8-image chunks.
   - Do not read the same image repeatedly unless a specific rule-level uncertainty requires it.
   - After each chunk, append the reviewed items to the draft JSON before reading the next chunk.
5. For each failed image, record rule-level issues with `description`, `suggestion`, and an optional `rule_id`.
6. Write an agent-authored draft JSON, then run `finalize` to create both a concise batch Markdown and `review_results.json`.

Do not hard-code web scraping as the default data source. For upload automation, use the NAS watcher script to create an isolated batch and trigger this review flow after upload completion.

When the user asks in natural language to "统计合格率", "统计某段时间合格率", "看一下本周/本月每个人通过率", or similar, do not review images again. Treat it as a statistics request: parse the requested date range, read `review-output/**/review_results.json`, and generate a pass-rate Markdown file under `review-output/stats/`. If the user did not provide a date range, ask which time period to use. Do not ask the user to run CLI commands manually.

## Commands

Count local images without using AI:

```bash
python3 <skill-dir>/scripts/image_review.py count 图片
```

After the current model has reviewed images, save a draft JSON and finalize it:

```bash
python3 <skill-dir>/scripts/image_review.py finalize review-draft.json \
  --input 图片 \
  --rules rules.md \
  --output-dir review-output/20260618-153000 \
  --report-output review-output/stats/2026-06-18.md
```

Draft JSON format:

```json
{
  "results": [
    {
      "person": "人名",
      "image_path": "图片/人名/example.png",
      "is_pass": false,
      "summary": "不合格",
      "issues": [
        {
          "rule_id": "logo",
          "description": "错误元素和证据",
          "suggestion": "修改方案"
        }
      ]
    }
  ]
}
```

`finalize` always saves the normalized JSON result as `review_results.json` in `--output-dir`.

Generate a time-range pass-rate summary when the user asks for statistics:

```bash
python3 <skill-dir>/scripts/image_review.py stats \
  --results-root review-output \
  --since 2026-06-01 \
  --until 2026-06-18 \
  --output review-output/stats/2026-06-01_2026-06-18.md
```

NAS watcher automation:

```bash
python3 <skill-dir>/scripts/setup_nas_watcher.py 图片 --baseline --install-launch-agent --start
python3 <skill-dir>/scripts/watch_nas_images.py --baseline
python3 <skill-dir>/scripts/watch_nas_images.py --once --dry-run
python3 <skill-dir>/scripts/watch_nas_images.py
```

Resolve `<skill-dir>` to this skill's directory before running bundled scripts. When the user asks to "listen/watch/monitor a mounted/NAS folder" and gives only a folder name, run `setup_nas_watcher.py <folder-name> --baseline --install-launch-agent --start`. The setup script resolves the mounted path under `/Volumes`, detects the current/default OpenClaw agent, writes user-local config under `~/.image-compliance-review/watchers/<agent>/`, installs a LaunchAgent, and starts the watcher. If it reports multiple matches or no match, ask the user to choose from the printed candidates.

If the user gives an exact path, run setup with `--watch-dir <path>` instead of a folder name. Do not ask users to edit JSON/plist files manually for normal setup.

The watcher reads setup-generated config by default when launched through LaunchAgent. Keep machine-specific values such as NAS mount path, agent id, OpenClaw binary path, and LaunchAgent plist outside the reusable skill unless packaging them as examples.

For each trigger, the watcher copies only the new batch into `.image-review-watcher/batch-inputs/<batch-id>/`. The review agent must finalize against that isolated batch input directory, not the original NAS root.

By default, setup stores batch JSON in the selected OpenClaw agent workspace at `review-output/<batch-id>/review_results.json` and the human-readable batch Markdown at `review-output/stats/YYYY-MM-DD.md`. Each automatic trigger is capped at 8 images and uses a unique `image-review-<batch-id>` session so base64 image reads do not accumulate in one long review session. Successful batch input directories are deleted after both output files exist; failed batch input directories are retained for debugging.

## Review Rules

When reviewing with the current model, produce structured issues with:

- `is_pass`: whether the image passes.
- `issues`: rule-level failures, including `rule_id`, `description`, and `suggestion`.
- `summary`: short image-level conclusion.

Do not generate marked or annotated image copies. The final user-facing output for a batch should be the concise Markdown batch review plus the persisted `review_results.json`.

If the current client/model cannot inspect images from an uploaded folder, state that limitation directly and ask the user to provide the images in a visible format. Do not switch to an external model workflow.

## Output Contract

Batch Markdown output must be concise and stable:

- Output path: `review-output/stats/YYYY-MM-DD.md`.
- Include batch id, audit time, total image count, passed count, failed count, manual-review count, and audit-error count.
- Include a per-person summary table with image count, passed count, failed count, manual-review count, and pass rate.
- In the image detail section, list only failed, manual-review, and audit-error images. Do not list passed images in Markdown.
- For each problem image, include image name, result, rule-level problem descriptions, and modification suggestions.
- Human-readable rule labels such as `Logo规范`, `文案规范`, and `市场雷区`; do not expose raw labels like `logo`, `copy`, or `market` in the Markdown report.
- If all images pass, write `本批未发现不合格或需人工复核图片。`
- Do not use emoji or decorative icons.

Use this style for problem images:

```text
人名
图片：图片名字
结果：不合格 / 需人工复核 / 审核错误
问题：
1. Logo规范：错误元素和证据
   修改方案：修改方案
```

Statistics Markdown output must be generated only when the user asks for statistics:

- Output path: `review-output/stats/YYYY-MM-DD_YYYY-MM-DD.md`.
- Read all matching `review-output/**/review_results.json` files.
- Filter by the requested audit date range.
- Aggregate per person: image total, passed, failed, manual-review, audit-error, issue count, and pass rate.
- Pass rate formula: `passed / (passed + failed + manual_review)`. Audit errors are excluded from the denominator. Manual-review images do not count as passed.
