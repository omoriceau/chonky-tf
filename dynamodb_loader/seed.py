"""
dynamodb_seed/seed.py

Loads local-dev sample data into the Users, Products, and Promotions
DynamoDB tables. Analogous to sql-data/02-init-data.sql for the old RDS
setup, but re-runnable safely (see ID note below).

Usage:
    USERS_TABLE=chonky-users-dev \
    PRODUCTS_TABLE=chonky-products-dev \
    PROMOTIONS_TABLE=chonky-promotions-dev \
    AWS_REGION=us-east-1 \
    python3 seed.py [path/to/dynamodb-seed.json]

Environment Variables:
    USERS_TABLE       Users table name
    PRODUCTS_TABLE    Products table name
    PROMOTIONS_TABLE  Promotions table name
    AWS_REGION        AWS region (default: us-east-1)

ID strategy note:
    The live application should mint fresh ULIDs for user_id/product_id
    when the app creates new records (sortable, no coordination needed —
    see the migration design). For *seed* data specifically we instead
    derive a deterministic id from each row's natural key (email / sku).
    That makes this script idempotent: running it again (e.g. on every
    `terraform apply`) overwrites the same items in place instead of
    minting new ids and leaving duplicates behind.
"""

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import boto3

SEED_NAMESPACE = uuid.UUID("6f6e9a2e-2f7a-4c1a-9c3e-8f1a6a7b0a10")


def deterministic_id(prefix: str, natural_key: str) -> str:
    """Stable id derived from a natural key, so re-seeding is idempotent."""
    return str(uuid.uuid5(SEED_NAMESPACE, f"{prefix}:{natural_key}"))


def to_decimal(value):
    """json gives floats; DynamoDB requires Decimal for numeric types."""
    if isinstance(value, float):
        return Decimal(str(value))
    return value


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_seed_data(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def seed_users(table, users: list) -> None:
    timestamp = now_iso()
    with table.batch_writer(overwrite_by_pkeys=["user_id"]) as batch:
        for user in users:
            item = {
                "user_id": deterministic_id("user", user["email"]),
                "email": user["email"],
                "first_name": user["first_name"],
                "last_name": user["last_name"],
                "phone": user["phone"],
                "role": user["role"],
                "status": user["status"],
                "created_at": timestamp,
                "updated_at": timestamp,
            }
            batch.put_item(Item=item)
    print(f"[users] wrote {len(users)} item(s)")


def seed_products(table, products: list) -> None:
    timestamp = now_iso()
    reorder_count = 0
    with table.batch_writer(overwrite_by_pkeys=["product_id"]) as batch:
        for product in products:
            item = {
                "product_id": deterministic_id("product", product["sku"]),
                "sku": product["sku"],
                "name": product["name"],
                "description": product["description"],
                "ingredients": product["ingredients"],
                "image_url": product["image_url"],
                "category": product["category"],
                "price": to_decimal(product["price"]),
                "qty": product["qty"],
                "low_stock_threshold": product["low_stock_threshold"],
                "active": product["active"],
                "created_at": timestamp,
                "updated_at": timestamp,
            }

            # Sparse GSI key: only present on items that currently need
            # reordering, so the reorder-report job can Query a tiny index
            # instead of scanning the whole catalog.
            if product["qty"] <= product["low_stock_threshold"]:
                item["reorder_flag"] = "REORDER"
                reorder_count += 1

            batch.put_item(Item=item)
    print(f"[products] wrote {len(products)} item(s), {reorder_count} flagged for reorder")


def seed_promotions(table, promotions: list) -> None:
    timestamp = now_iso()
    with table.batch_writer(overwrite_by_pkeys=["code"]) as batch:
        for promo in promotions:
            item = {
                "code": promo["code"],
                "discount_type": promo["discount_type"],
                "discount_value": to_decimal(promo["discount_value"]),
                "active": promo["active"],
                "created_at": timestamp,
            }
            batch.put_item(Item=item)
    print(f"[promotions] wrote {len(promotions)} item(s)")


def main():
    users_table_name = os.environ["USERS_TABLE"]
    products_table_name = os.environ["PRODUCTS_TABLE"]
    promotions_table_name = os.environ["PROMOTIONS_TABLE"]
    region = os.environ.get("AWS_REGION", "us-east-1")

    data_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "seed-data", "dynamodb-seed.json"
    )

    data = load_seed_data(data_path)

    dynamodb = boto3.resource("dynamodb", region_name=region)

    seed_users(dynamodb.Table(users_table_name), data["users"])
    seed_products(dynamodb.Table(products_table_name), data["products"])
    seed_promotions(dynamodb.Table(promotions_table_name), data["promotions"])

    print("Seed complete.")


if __name__ == "__main__":
    main()
