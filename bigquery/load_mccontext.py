#!/usr/bin/env python3
"""
load_mccontext.py
=================
Creates the BigQuery datasets and synthetic data that back the LookML demo.

Project:   salesengineering-2022
Datasets:  mccontext_silver (raw-ish facts), mccontext_gold (curated views)
Tables:    mccontext_silver.fact_cases, mccontext_gold.customer_360

Run:
    pip install google-cloud-bigquery faker --break-system-packages
    gcloud auth application-default login
    python load_mccontext.py

Tunables at the top of main(). Defaults: 500 customers, ~2000 cases.

The synthetic data is internally consistent: each customer_360 row's
open_case_count matches the actual number of open cases in fact_cases for that
customer, so demo answers will agree across explores.
"""

import random
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from faker import Faker
from google.cloud import bigquery

PROJECT_ID = "salesengineering-2022"
SILVER_DATASET = "mccontext_silver"
GOLD_DATASET = "mccontext_gold"
LOCATION = "US"  # change if your BQ region differs

fake = Faker()
random.seed(42)
Faker.seed(42)


# -----------------------------------------------------------------------------
# Schemas
# -----------------------------------------------------------------------------

FACT_CASES_SCHEMA = [
    bigquery.SchemaField("ticket_id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("ticket_number", "STRING"),
    bigquery.SchemaField("customer_id", "INT64"),
    bigquery.SchemaField("status", "STRING"),
    bigquery.SchemaField("priority", "STRING"),
    bigquery.SchemaField("assigned_team", "STRING"),
    bigquery.SchemaField("current_assignee_id", "INT64"),
    bigquery.SchemaField("resolution_type", "STRING"),
    bigquery.SchemaField("intent_classified", "STRING"),
    bigquery.SchemaField("linked_charge_count", "INT64"),
    bigquery.SchemaField("linked_order_count", "INT64"),
    bigquery.SchemaField("linked_refund_count", "INT64"),
    bigquery.SchemaField("opened_at", "TIMESTAMP"),
    bigquery.SchemaField("first_response_at", "TIMESTAMP"),
    bigquery.SchemaField("closed_at", "TIMESTAMP"),
    bigquery.SchemaField("credit_amount_usd", "NUMERIC"),
    bigquery.SchemaField("refund_amount_usd", "NUMERIC"),
    bigquery.SchemaField("time_to_first_response_seconds", "INT64"),
    bigquery.SchemaField("time_to_resolution_seconds", "INT64"),
]

CUSTOMER_360_SCHEMA = [
    bigquery.SchemaField("customer_id", "INT64", mode="REQUIRED"),
    bigquery.SchemaField("full_name", "STRING"),
    bigquery.SchemaField("email", "STRING"),
    bigquery.SchemaField("phone", "STRING"),
    bigquery.SchemaField("plus_subscriber", "BOOL"),
    bigquery.SchemaField("loyalty_tier", "STRING"),
    bigquery.SchemaField("subscription_plan", "STRING"),
    bigquery.SchemaField("signup_date", "DATE"),
    bigquery.SchemaField("last_order_at", "TIMESTAMP"),
    bigquery.SchemaField("refreshed_at", "TIMESTAMP"),
    bigquery.SchemaField("lifetime_spend_usd", "NUMERIC"),
    bigquery.SchemaField("lifetime_refund_usd", "NUMERIC"),
    bigquery.SchemaField("avg_csat_last_5", "NUMERIC"),
    bigquery.SchemaField("lifetime_orders", "INT64"),
    bigquery.SchemaField("open_case_count", "INT64"),
    bigquery.SchemaField("lifetime_case_count", "INT64"),
    bigquery.SchemaField("earn_multiplier", "NUMERIC"),
    bigquery.SchemaField("mrr_usd", "NUMERIC"),
]


# -----------------------------------------------------------------------------
# Data generation
# -----------------------------------------------------------------------------

LOYALTY_TIERS = ["Bronze", "Silver", "Gold", "Platinum"]
TIER_WEIGHTS = [0.50, 0.30, 0.15, 0.05]
TIER_MULTIPLIER = {"Bronze": 1.0, "Silver": 1.25, "Gold": 1.5, "Platinum": 2.0}

SUBSCRIPTION_PLANS = ["Free", "Plus Monthly", "Plus Annual", "Plus Family"]

CASE_STATUSES = ["open", "pending", "resolved", "closed", "escalated"]
STATUS_WEIGHTS = [0.08, 0.07, 0.25, 0.55, 0.05]

PRIORITIES = ["low", "normal", "high", "critical"]
PRIORITY_WEIGHTS = [0.30, 0.50, 0.15, 0.05]

TEAMS = ["T1-Frontline", "T2-Billing", "T2-Quality", "T3-Engineering", "Trust&Safety"]

INTENTS = ["food_quality", "double_charge", "outage", "refund_request",
           "delivery_late", "account_access", "promo_redemption"]

RESOLUTION_TYPES = ["Closed - no action", "refund", "credit", "escalation",
                    "duplicate_charge_reversal", "replacement"]


def generate_customers(n_customers: int):
    rows = []
    now = datetime.now(timezone.utc)
    for cid in range(1, n_customers + 1):
        tier = random.choices(LOYALTY_TIERS, weights=TIER_WEIGHTS)[0]
        is_plus = random.random() < (0.2 if tier == "Bronze" else
                                     0.45 if tier == "Silver" else
                                     0.70 if tier == "Gold" else 0.95)
        plan = random.choice(SUBSCRIPTION_PLANS[1:]) if is_plus else "Free"
        signup = fake.date_between(start_date="-3y", end_date="-30d")
        last_order = fake.date_time_between(
            start_date=datetime.combine(signup, datetime.min.time()),
            end_date=now.replace(tzinfo=None),
            tzinfo=timezone.utc,
        )
        lifetime_orders = random.randint(1, 200) if tier != "Bronze" else random.randint(1, 30)
        avg_order_value = random.uniform(8, 45) * TIER_MULTIPLIER[tier]
        lifetime_spend = round(lifetime_orders * avg_order_value, 2)
        lifetime_refund = round(lifetime_spend * random.uniform(0.0, 0.08), 2)
        avg_csat = round(random.uniform(
            2.5 if tier == "Bronze" else 3.2,
            5.0
        ), 2)
        mrr = {"Free": 0.0,
               "Plus Monthly": 9.99,
               "Plus Annual": 7.99,
               "Plus Family": 14.99}[plan]

        rows.append({
            "customer_id": cid,
            "full_name": fake.name(),
            "email": fake.email(),
            "phone": fake.phone_number()[:20],
            "plus_subscriber": is_plus,
            "loyalty_tier": tier,
            "subscription_plan": plan,
            "signup_date": signup.isoformat(),
            "last_order_at": last_order.isoformat(),
            "refreshed_at": now.isoformat(),
            "lifetime_spend_usd": str(Decimal(str(lifetime_spend))),
            "lifetime_refund_usd": str(Decimal(str(lifetime_refund))),
            "avg_csat_last_5": str(Decimal(str(avg_csat))),
            "lifetime_orders": lifetime_orders,
            # open_case_count and lifetime_case_count filled in after cases generated
            "open_case_count": 0,
            "lifetime_case_count": 0,
            "earn_multiplier": str(Decimal(str(TIER_MULTIPLIER[tier]))),
            "mrr_usd": str(Decimal(str(mrr))),
        })
    return rows


def generate_cases(customers, target_total_cases: int):
    rows = []
    now = datetime.now(timezone.utc)
    n = len(customers)
    # weighted: high-tier customers contact support a bit more often (more product surface)
    weights = []
    for c in customers:
        base = 1.0
        if c["loyalty_tier"] == "Gold":
            base = 1.5
        elif c["loyalty_tier"] == "Platinum":
            base = 2.0
        if c["plus_subscriber"]:
            base *= 1.4
        weights.append(base)

    assignments = random.choices(range(n), weights=weights, k=target_total_cases)
    open_counts = {c["customer_id"]: 0 for c in customers}
    lifetime_counts = {c["customer_id"]: 0 for c in customers}

    for i, idx in enumerate(assignments, start=1):
        customer = customers[idx]
        opened = fake.date_time_between(start_date="-365d", end_date="now",
                                        tzinfo=timezone.utc)
        status = random.choices(CASE_STATUSES, weights=STATUS_WEIGHTS)[0]
        priority = random.choices(PRIORITIES, weights=PRIORITY_WEIGHTS)[0]
        intent = random.choice(INTENTS)

        ttfr_sec = max(60, int(random.expovariate(1 / 1800)))  # mean ~30 min
        first_response = opened + timedelta(seconds=ttfr_sec)

        if status in ("open", "pending"):
            closed = None
            ttr_sec = None
        else:
            ttr_sec = max(ttfr_sec + 60, int(random.expovariate(1 / 14400)))  # mean ~4h
            closed = opened + timedelta(seconds=ttr_sec)

        # resolution_type only meaningful when closed
        if status in ("resolved", "closed"):
            res_type = random.choice(RESOLUTION_TYPES)
        elif status == "escalated":
            res_type = "escalation"
        else:
            res_type = None

        credit_amt = round(random.uniform(0, 25), 2) if res_type == "credit" else 0.0
        refund_amt = round(random.uniform(5, 80), 2) if res_type in (
            "refund", "duplicate_charge_reversal") else 0.0

        rows.append({
            "ticket_id": str(uuid.uuid4()),
            "ticket_number": f"MC-{100000 + i}",
            "customer_id": customer["customer_id"],
            "status": status,
            "priority": priority,
            "assigned_team": random.choice(TEAMS),
            "current_assignee_id": random.randint(1000, 1099),
            "resolution_type": res_type,
            "intent_classified": intent,
            "linked_charge_count": random.choices([0, 1, 2, 3],
                                                  weights=[0.55, 0.30, 0.10, 0.05])[0],
            "linked_order_count": random.choices([0, 1, 2],
                                                 weights=[0.40, 0.50, 0.10])[0],
            "linked_refund_count": 1 if refund_amt > 0 else 0,
            "opened_at": opened.isoformat(),
            "first_response_at": first_response.isoformat(),
            "closed_at": closed.isoformat() if closed else None,
            "credit_amount_usd": str(Decimal(str(credit_amt))),
            "refund_amount_usd": str(Decimal(str(refund_amt))),
            "time_to_first_response_seconds": ttfr_sec,
            "time_to_resolution_seconds": ttr_sec,
        })

        lifetime_counts[customer["customer_id"]] += 1
        if status in ("open", "pending"):
            open_counts[customer["customer_id"]] += 1

    # back-fill the open/lifetime case counts on the customer rows
    for c in customers:
        c["open_case_count"] = open_counts[c["customer_id"]]
        c["lifetime_case_count"] = lifetime_counts[c["customer_id"]]

    return rows


# -----------------------------------------------------------------------------
# BigQuery load
# -----------------------------------------------------------------------------

def ensure_dataset(client: bigquery.Client, dataset_id: str):
    ref = bigquery.Dataset(f"{PROJECT_ID}.{dataset_id}")
    ref.location = LOCATION
    client.create_dataset(ref, exists_ok=True)
    print(f"[OK] Dataset {PROJECT_ID}.{dataset_id} ready")


def load_table(client: bigquery.Client, dataset_id: str, table_id: str,
               schema, rows):
    table_ref = f"{PROJECT_ID}.{dataset_id}.{table_id}"
    # drop and recreate so re-runs are idempotent
    client.delete_table(table_ref, not_found_ok=True)
    table = bigquery.Table(table_ref, schema=schema)
    client.create_table(table)
    print(f"[OK] Table {table_ref} created")

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    import io, json
    buf = io.BytesIO()
    for r in rows:
        buf.write((json.dumps(r) + "\n").encode("utf-8"))
    buf.seek(0)
    job = client.load_table_from_file(buf, table_ref, job_config=job_config)
    job.result()
    print(f"[OK] Loaded {len(rows)} rows into {table_ref}")


def main():
    n_customers = 500
    target_cases = 2000

    print(f"Generating {n_customers} customers and ~{target_cases} cases...")
    customers = generate_customers(n_customers)
    cases = generate_cases(customers, target_cases)

    client = bigquery.Client(project=PROJECT_ID)
    ensure_dataset(client, SILVER_DATASET)
    ensure_dataset(client, GOLD_DATASET)

    load_table(client, SILVER_DATASET, "fact_cases", FACT_CASES_SCHEMA, cases)
    load_table(client, GOLD_DATASET, "customer_360", CUSTOMER_360_SCHEMA, customers)

    print("\nDone. Verify in BQ console:")
    print(f"  SELECT status, COUNT(*) FROM `{PROJECT_ID}.{SILVER_DATASET}.fact_cases` GROUP BY 1;")
    print(f"  SELECT loyalty_tier, COUNT(*) FROM `{PROJECT_ID}.{GOLD_DATASET}.customer_360` GROUP BY 1;")


if __name__ == "__main__":
    main()
