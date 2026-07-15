"""Seed synthetic data into the indices used by the Golden Signals dashboards.

Run once before `terraform apply` so the panels render with realistic data.

Required environment variables (loaded from .env if present):
    ELASTICSEARCH_URL      Elasticsearch URL (e.g. https://...es.cloud.es.io)
    ELASTICSEARCH_API_KEY  API key with write privileges on the target data streams
"""

import datetime as dt
import os
import random

from dotenv import load_dotenv

load_dotenv()

from elasticsearch import Elasticsearch, helpers

ES_ENDPOINT = os.environ["ELASTICSEARCH_URL"]
ES_API_KEY = os.environ["ELASTICSEARCH_API_KEY"]

es = Elasticsearch(
    ES_ENDPOINT,
    api_key=ES_API_KEY,
)

NOW = dt.datetime.now(dt.timezone.utc)


def ts(i: int, total: int) -> str:
    return (NOW - dt.timedelta(minutes=total - i)).isoformat()


def gen(index, total, builder):
    for i in range(total):
        yield {
            "_op_type": "create",
            "_index": index,
            "_source": builder(i, total),
        }


def payments(i, n):
    return {
        "@timestamp": ts(i, n),
        "duration_ms": max(20, int(random.gauss(180, 80))),
        "provider_ms": max(10, int(random.gauss(90, 40))),
        "status": random.choices([200, 400, 500], weights=[92, 5, 3])[0],
    }


def checkout(i, n):
    return {
        "@timestamp": ts(i, n),
        "duration_ms": max(20, int(random.gauss(150, 60))),
        "cart_total": round(random.uniform(10, 250), 2),
        "status": random.choices([200, 400, 500], weights=[95, 3, 2])[0],
    }


def metrics(i, n):
    return {
        "@timestamp": ts(i, n),
        # host.name is the TSDS dimension field (see metrics_tsds.tf).
        "host": {"name": f"payments-host-{i % 3}"},
        "cpu": {"pct": round(0.4 + 0.3 * random.random(), 3)},
    }


for index, total, builder in [
    ("logs-payments-default", 500, payments),
    ("logs-checkout-default", 400, checkout),
    ("metrics-payments-default", 300, metrics),
]:
    try:
        helpers.bulk(es, gen(index, total, builder))
    except helpers.BulkIndexError as exc:
        print(f"failed to seed {index}: {exc.errors[0]}")
        raise
    print(f"seeded {total} docs into {index}")
