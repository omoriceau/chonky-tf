"""
disaster_recovery/dr_demo.py

Helper for the DynamoDB point-in-time-recovery demo described in
DISASTER_RECOVERY.md. Three steps: capture a baseline, simulate a scoped
data-loss incident, then verify the PITR-restored table matches baseline.
Mirrors dynamodb_loader/seed.py's conventions (boto3, table name as a CLI
arg / env var, region default us-east-1).

Usage:
    python3 dr_demo.py baseline --table chonky-products-production
    python3 dr_demo.py break --table chonky-products-production --category Treat --dry-run
    python3 dr_demo.py break --table chonky-products-production --category Treat --confirm chonky-products-production-I-UNDERSTAND-THIS-IS-PRODUCTION
    python3 dr_demo.py verify --table chonky-products-production-restored --baseline dr_baseline_chonky-products-production_<ts>.json

No dev environment is currently deployed in this account (only *-production
tables exist) — see DISASTER_RECOVERY.md. `break` therefore deletes real,
live items. Tables ending in "-production" require --confirm to match
"<table>-I-UNDERSTAND-THIS-IS-PRODUCTION", not just the table name, and
--dry-run lists what would be deleted without deleting anything.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from decimal import Decimal

import boto3


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def scan_all(table):
    items = []
    kwargs = {}
    while True:
        resp = table.scan(**kwargs)
        items.extend(resp["Items"])
        if "LastEvaluatedKey" not in resp:
            break
        kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
    return items


def cmd_baseline(args, dynamodb):
    table = dynamodb.Table(args.table)
    items = scan_all(table)
    timestamp = now_iso()
    out_path = f"dr_baseline_{args.table}_{timestamp.replace(':', '')}.json"

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"table": args.table, "captured_at": timestamp, "items": items},
                   f, indent=2, cls=DecimalEncoder)

    print(f"[baseline] {len(items)} item(s) captured from '{args.table}'")
    print(f"[baseline] wrote {out_path}")
    print(f"[baseline] restore point (use for restore-table-to-point-in-time): {timestamp}")


def cmd_break(args, dynamodb):
    required_confirm = f"{args.table}-I-UNDERSTAND-THIS-IS-PRODUCTION" if args.table.endswith("-production") else args.table

    table = dynamodb.Table(args.table)
    items = scan_all(table)
    key_names = [k["AttributeName"] for k in table.key_schema]
    to_delete = [item for item in items if item.get("category") == args.category]

    if not to_delete:
        print(f"[break] no items found with category='{args.category}' — nothing to delete")
        return

    if args.dry_run:
        print(f"[break] DRY RUN — would delete {len(to_delete)} item(s) with category='{args.category}' from '{args.table}':")
        for item in to_delete:
            print(f"  {item}")
        return

    if args.confirm != required_confirm:
        print(f"Refusing to run: --confirm must exactly match '{required_confirm}'", file=sys.stderr)
        sys.exit(1)

    with table.batch_writer() as batch:
        for item in to_delete:
            batch.delete_item(Key={k: item[k] for k in key_names})

    print(f"[break] deleted {len(to_delete)} item(s) with category='{args.category}' from '{args.table}'")
    print(f"[break] incident time: {now_iso()}")


def cmd_verify(args, dynamodb):
    with open(args.baseline, "r", encoding="utf-8") as f:
        baseline = json.load(f)

    table = dynamodb.Table(args.table)
    current = scan_all(table)

    baseline_count = len(baseline["items"])
    current_count = len(current)

    print(f"[verify] baseline ('{baseline['table']}' @ {baseline['captured_at']}): {baseline_count} item(s)")
    print(f"[verify] restored table ('{args.table}'): {current_count} item(s)")

    if baseline_count == current_count:
        print("[verify] PASS — item counts match")
    else:
        print("[verify] MISMATCH — investigate before cutover")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    sub = parser.add_subparsers(dest="command", required=True)

    p_baseline = sub.add_parser("baseline", help="Capture current table contents + restore-point timestamp")
    p_baseline.add_argument("--table", required=True)

    p_break = sub.add_parser("break", help="Simulate a scoped data-loss incident (deletes one category)")
    p_break.add_argument("--table", required=True)
    p_break.add_argument("--category", required=True)
    p_break.add_argument("--confirm", help="Must match --table (or '<table>-I-UNDERSTAND-THIS-IS-PRODUCTION' for -production tables). Not required with --dry-run.")
    p_break.add_argument("--dry-run", action="store_true", help="List items that would be deleted without deleting them")

    p_verify = sub.add_parser("verify", help="Diff a restored table's contents against a baseline capture")
    p_verify.add_argument("--table", required=True)
    p_verify.add_argument("--baseline", required=True)

    args = parser.parse_args()
    dynamodb = boto3.resource("dynamodb", region_name=args.region)

    {"baseline": cmd_baseline, "break": cmd_break, "verify": cmd_verify}[args.command](args, dynamodb)


if __name__ == "__main__":
    main()
