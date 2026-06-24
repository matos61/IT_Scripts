#!/usr/bin/env python3
"""
inactive-license-audit.py — find Atlassian (or any SaaS) seats safe to reclaim.

Reads a managed-accounts CSV export, flags Active human users who have been
inactive for N+ days, and separates out service/bot accounts so they aren't
mistakenly deprovisioned.

The bot-detection is heuristic (email/name patterns). Site-specific service
account names can be supplied via --bots-file (one local-part or email per
line) instead of being hard-coded — keep your real account names out of source.

Usage:
  ./inactive-license-audit.py accounts.csv \
      --out inactive.csv --bots-out excluded_bots.csv \
      --cutoff-days 60 [--as-of 2026-04-07] [--bots-file known_bots.txt]
"""
import argparse
import csv
import re
import sys
from datetime import datetime, date

# Generic service-account local-parts. Override/extend with --bots-file so your
# organisation's real account names never live in a public repo.
DEFAULT_BOT_LOCALPARTS = {
    "noreply", "no-reply", "donotreply", "mailer-daemon",
    "service", "service-account", "svc", "automation", "ci", "ci-bot",
    "integration", "etl-robot", "monitoring-robot",
}


def is_bot(name: str, email: str, extra_bots: set) -> bool:
    """Detect service/bot accounts while avoiding false positives on human names."""
    name_l = name.lower()
    local = email.lower().split("@")[0]

    # Email-based signals (high confidence)
    if local.startswith(("bots+", "bots-", "noreply", "noreply+")):
        return True
    if "noreply" in local:
        return True
    if re.search(r"\brobot\b", local) or local.endswith("robot"):
        return True
    if re.search(r"\bbot\b", local) or local.endswith("bot"):
        return True
    if local in DEFAULT_BOT_LOCALPARTS or local in extra_bots or email.lower() in extra_bots:
        return True

    # Name-based signals — word boundaries avoid "Chebotov", "Botfield", etc.
    if re.search(r"\bbot\b", name_l) or re.search(r"\brobot\b", name_l):
        return True
    if re.search(r"(^|\s)\w*bot$", name_l) or re.search(r"(^|\s)\w*robot$", name_l):
        return True
    if re.search(r"\b(system user|integration|daemon|service account)\b", name_l):
        return True

    return False


def main(argv=None):
    ap = argparse.ArgumentParser(description="Find inactive SaaS license holders from a managed-accounts CSV.")
    ap.add_argument("input", help="managed-accounts CSV export")
    ap.add_argument("--out", default="inactive_license_holders.csv", help="output CSV of inactive humans")
    ap.add_argument("--bots-out", default="excluded_bots.csv", help="output CSV of excluded service accounts")
    ap.add_argument("--cutoff-days", type=int, default=60, help="days of inactivity to flag (default 60)")
    ap.add_argument("--as-of", help="reference date YYYY-MM-DD (default: today)")
    ap.add_argument("--bots-file", help="extra service-account local-parts/emails, one per line")
    args = ap.parse_args(argv)

    today = datetime.strptime(args.as_of, "%Y-%m-%d").date() if args.as_of else date.today()

    extra_bots = set()
    if args.bots_file:
        with open(args.bots_file, encoding="utf-8") as f:
            extra_bots = {line.strip().lower() for line in f if line.strip() and not line.startswith("#")}

    results, bots_excluded = [], []
    with open(args.input, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("Status", "").strip() != "Active":
                continue
            name = row.get("Name", "").strip()
            email = row.get("Email", "").strip()
            if is_bot(name, email, extra_bots):
                bots_excluded.append(row)
                continue

            last_active_raw = row.get("Last active date [UTC]", "").strip()
            if not last_active_raw:
                row["Days Since Last Active"] = "Never active"
                results.append(row)
                continue
            try:
                days = (today - datetime.strptime(last_active_raw, "%Y-%m-%d").date()).days
            except ValueError:
                continue
            if days >= args.cutoff_days:
                row["Days Since Last Active"] = days
                results.append(row)

    results.sort(key=lambda r: (
        0 if r["Days Since Last Active"] == "Never active" else 1,
        -(r["Days Since Last Active"] if r["Days Since Last Active"] != "Never active" else 99999),
    ))

    out_headers = ["Name", "Email", "Status", "Last active date [UTC]", "Days Since Last Active"]
    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=out_headers, extrasaction="ignore")
        w.writeheader(); w.writerows(results)

    bot_headers = ["Name", "Email", "Status", "Last active date [UTC]"]
    with open(args.bots_out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=bot_headers, extrasaction="ignore")
        w.writeheader(); w.writerows(bots_excluded)

    never = sum(1 for r in results if r["Days Since Last Active"] == "Never active")
    print(f"Done. {len(results)} active humans inactive {args.cutoff_days}+ days "
          f"({never} never active). Excluded {len(bots_excluded)} service accounts.")
    print(f"  inactive -> {args.out}\n  excluded -> {args.bots_out}")


if __name__ == "__main__":
    sys.exit(main())
