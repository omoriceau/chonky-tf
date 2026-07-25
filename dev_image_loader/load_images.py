#!/usr/bin/env python3
# Uploads base_imgs/* to S3 as per-SKU test images (img/<sku>.jpg), matching
# the naming convention chonky-cat-fe expects (see its scripts/init-images.mjs).
# Reads product sku/category straight from dynamodb_loader's seed data instead
# of hitting the live product API, so this deployment has no runtime
# dependency on the frontend repo or a deployed API.

import json
import os
import sys

import boto3

BUCKET = os.environ["IMAGES_BUCKET"]
SEED_DATA_PATH = os.environ["SEED_DATA_PATH"]
BASE_IMGS_DIR = os.environ["BASE_IMGS_DIR"]
REGION = os.environ.get("AWS_REGION", "us-east-1")

# Substring match against each product's category (case-insensitive) -> base image.
CATEGORY_BASE_IMAGE = {
    "wet": "wet.jpg",
    "dry": "dry.jpg",
    "treat": "treat.jpg",
}


def base_image_for(category: str) -> str | None:
    category = (category or "").lower()
    for needle, filename in CATEGORY_BASE_IMAGE.items():
        if needle in category:
            return filename
    return None


def main() -> None:
    for filename in set(CATEGORY_BASE_IMAGE.values()):
        path = os.path.join(BASE_IMGS_DIR, filename)
        if not os.path.exists(path):
            raise SystemExit(f"[load_images] Missing base image: {path}")

    with open(SEED_DATA_PATH) as f:
        products = json.load(f)["products"]

    s3 = boto3.client("s3", region_name=REGION)

    counts: dict[str, int] = {}
    skipped: list[str] = []

    for product in products:
        sku = product.get("sku")
        category = product.get("category", "")

        if not sku:
            skipped.append(f"(missing sku) {product.get('name', '?')}")
            continue

        base_image = base_image_for(category)
        if not base_image:
            skipped.append(f"{sku} (unrecognized category '{category}')")
            continue

        src = os.path.join(BASE_IMGS_DIR, base_image)
        key = f"img/{sku.lower()}.jpg"

        with open(src, "rb") as fh:
            s3.put_object(Bucket=BUCKET, Key=key, Body=fh.read(), ContentType="image/jpeg")

        counts[category] = counts.get(category, 0) + 1

    total = sum(counts.values())
    print(f"[load_images] Uploaded {total} image(s) to s3://{BUCKET}/img/")
    for category, count in counts.items():
        print(f"  {category}: {count}")
    if skipped:
        print(f"[load_images] Skipped {len(skipped)} product(s):", file=sys.stderr)
        for s in skipped:
            print(f"  - {s}", file=sys.stderr)


if __name__ == "__main__":
    main()
