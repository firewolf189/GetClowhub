#!/usr/bin/env python3
"""
从 agency-agents README.md 表格中提取 Specialty 和 When to Use，
合并到 marketplace_agents.json。

用法:
    python3 scripts/enrich_marketplace.py \
        --readme /tmp/agency-agents/README.md \
        --json OpenClawInstaller/OpenClawInstaller/Resources/marketplace_agents.json
"""
import json
import re
import argparse
from pathlib import Path


def parse_readme_tables(readme_path: str) -> dict:
    """Parse all markdown tables from README, extract agent name -> (specialty, when_to_use)."""
    text = Path(readme_path).read_text(encoding="utf-8")

    # Match table rows: | emoji [Name](link) | Specialty | When to Use |
    # Also match: | emoji [Name](link) | Specialty text | When to use text |
    pattern = re.compile(
        r'^\|\s*\S+\s+\[([^\]]+)\]\([^)]+\)\s*\|\s*([^|]+)\|\s*([^|]+)\|',
        re.MULTILINE
    )

    agents = {}
    for m in pattern.finditer(text):
        name = m.group(1).strip()
        specialty = m.group(2).strip()
        when_to_use = m.group(3).strip()

        # Skip header rows
        if specialty == "Specialty" or specialty.startswith("---"):
            continue

        agents[name] = {
            "specialty": specialty,
            "whenToUse": when_to_use,
        }

    return agents


def normalize_name(name: str) -> str:
    """Normalize agent name for fuzzy matching.
    Strips parenthetical suffixes, common filler words, and punctuation differences.
    """
    name = name.lower().strip()
    # Remove parenthetical suffixes like "(Site Reliability Engineer)"
    name = re.sub(r'\s*\([^)]*\)', '', name)
    # Normalize hyphens and spaces
    name = name.replace('-', ' ').replace('_', ' ')
    # Normalize "add-on" vs "addon"
    name = name.replace('add on', 'addon')
    # Remove trailing "specialist" for better matching
    name = re.sub(r'\s+specialist$', '', name)
    return name.strip()


def merge_data(json_path: str, readme_agents: dict) -> tuple:
    """Merge README data into marketplace_agents.json. Returns (updated_data, stats)."""
    with open(json_path, "r", encoding="utf-8") as f:
        agents = json.load(f)

    # Build lookup by normalized name
    readme_lookup = {normalize_name(k): v for k, v in readme_agents.items()}

    matched = 0
    unmatched_json = []

    for agent in agents:
        key = normalize_name(agent["name"])
        if key in readme_lookup:
            agent["specialty"] = readme_lookup[key]["specialty"]
            agent["whenToUse"] = readme_lookup[key]["whenToUse"]
            matched += 1
        else:
            unmatched_json.append(agent["name"])

    # Find README agents not in JSON
    json_names = {normalize_name(a["name"]) for a in agents}
    unmatched_readme = [name for name in readme_agents if normalize_name(name) not in json_names]

    stats = {
        "total_json": len(agents),
        "total_readme": len(readme_agents),
        "matched": matched,
        "unmatched_json": unmatched_json,
        "unmatched_readme": unmatched_readme,
    }

    return agents, stats


def main():
    parser = argparse.ArgumentParser(description="Enrich marketplace_agents.json with README data")
    parser.add_argument("--readme", required=True, help="Path to agency-agents README.md")
    parser.add_argument("--json", required=True, help="Path to marketplace_agents.json")
    parser.add_argument("--dry-run", action="store_true", help="Print stats without writing")
    args = parser.parse_args()

    print(f"Parsing README: {args.readme}")
    readme_agents = parse_readme_tables(args.readme)
    print(f"  Found {len(readme_agents)} agents in README tables")

    print(f"\nMerging into: {args.json}")
    updated, stats = merge_data(args.json, readme_agents)

    print(f"\n  JSON agents:   {stats['total_json']}")
    print(f"  README agents: {stats['total_readme']}")
    print(f"  Matched:       {stats['matched']}")
    print(f"  Unmatched JSON ({len(stats['unmatched_json'])}):")
    for name in stats['unmatched_json'][:10]:
        print(f"    - {name}")
    if len(stats['unmatched_json']) > 10:
        print(f"    ... and {len(stats['unmatched_json']) - 10} more")

    print(f"  Unmatched README ({len(stats['unmatched_readme'])}):")
    for name in stats['unmatched_readme'][:10]:
        print(f"    - {name}")
    if len(stats['unmatched_readme']) > 10:
        print(f"    ... and {len(stats['unmatched_readme']) - 10} more")

    if args.dry_run:
        print("\n[DRY RUN] No files written.")
    else:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(updated, f, ensure_ascii=False, indent=2)
        print(f"\n  Written to {args.json}")


if __name__ == "__main__":
    main()
