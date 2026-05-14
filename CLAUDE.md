# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project context — General Mills demo (Atlan Context Repo → LookML)

## What this project is

A 10–15 minute customer demo for General Mills showing that Atlan's Context Repo YAML files (extracted from on-prem Tableau) can be projected into LookML and queried deterministically in Looker via Gemini Conversational Analytics on top of BigQuery.

**Demo date:** Friday 2026-05-15. Prep happens Thursday.

**Source of truth for this project:** `DEMO_PLAN.md`. Read it before doing anything. It contains the full narrative, build phases, demo script, and risk register. Treat it as the spec.

**Domain note:** The two YAMLs (`fact_cases.yaml`, `customer_360.yaml`) describe customer-support data for a fictional business called "McContext", *not* supply-chain data. The demo positions this to General Mills as "imagine this is your customer-support data coming out of Tableau."

## File map

```
fact_cases.yaml                       Atlan Context Repo source (do not modify)
customer_360.yaml                     Atlan Context Repo source (do not modify)
DEMO_PLAN.md                          The runbook — source of truth
lookml/
  manifest.lkml
  mccontext.model.lkml                connection: "bq_mccontext", two explores
  views/fact_cases.view.lkml          Derived from fact_cases.yaml
  views/customer_360.view.lkml        Derived from customer_360.yaml
bigquery/
  load_mccontext.py                   Creates datasets + loads 500 customers, ~2000 cases
```

## Key facts (use these verbatim, do not rename)

| Thing | Value |
|---|---|
| GCP project | `salesengineering-2022` |
| BigQuery datasets | `mccontext_silver`, `mccontext_gold` |
| BigQuery tables | `mccontext_silver.fact_cases`, `mccontext_gold.customer_360` |
| Looker scratch dataset (PDTs) | `looker_scratch` |
| Service account name | `looker-mccontext-reader@salesengineering-2022.iam.gserviceaccount.com` |
| SA JSON key local path | `~/looker-mccontext-reader.json` |
| Looker instance | `https://atlan.cloud.looker.com/` |
| Looker connection name | `bq_mccontext` (must match `connection:` in mccontext.model.lkml) |
| Looker project name | `mccontext_demo` |
| Synthetic data seed | `42` (deterministic across re-runs) |

---

## Commands

### Install dependencies

```bash
pip install google-cloud-bigquery faker --break-system-packages
```

### Authenticate to GCP

```bash
gcloud auth application-default login
gcloud config set project salesengineering-2022
```

Check auth status (do not run `gcloud auth login` — prompt the user to run it themselves if needed):

```bash
gcloud auth list
gcloud config get-value project
```

### Load synthetic data into BigQuery

Takes ~30–60 seconds. Re-running is idempotent (drops and recreates both tables).

```bash
cd /Users/hari.rongali/Desktop/Customers/general_mills/bigquery
python load_mccontext.py
```

### Verify BigQuery data

```bash
bq ls salesengineering-2022:mccontext_silver
bq ls salesengineering-2022:mccontext_gold
```

### Sanity-check queries (run in BQ console or via `bq query`)

```sql
-- Status distribution: closed ~55%, resolved ~25%, open ~8%, pending ~7%, escalated ~5%
SELECT status, COUNT(*) AS n FROM `salesengineering-2022.mccontext_silver.fact_cases`
GROUP BY 1 ORDER BY n DESC;

-- Tier distribution: Bronze 50%, Silver 30%, Gold 15%, Platinum 5%
SELECT loyalty_tier, COUNT(*) AS n FROM `salesengineering-2022.mccontext_gold.customer_360`
GROUP BY 1 ORDER BY n DESC;

-- Cross-table consistency: expect zero rows (open_case_count must match actual open/pending cases)
SELECT c.customer_id, c.open_case_count AS reported,
       COUNT(CASE WHEN f.status IN ('open','pending') THEN 1 END) AS actual
FROM `salesengineering-2022.mccontext_gold.customer_360` c
LEFT JOIN `salesengineering-2022.mccontext_silver.fact_cases` f USING (customer_id)
GROUP BY 1, 2 HAVING reported != actual;
```

### LookML validation

Must be done in the Looker UI (Develop → mccontext_demo → Validate LookML). There is no CLI validator available for this instance.

### Push LookML via Git (if a remote is configured)

```bash
cd /Users/hari.rongali/Desktop/Customers/general_mills/lookml
git init && git add . && git commit -m "Initial LookML from Atlan Context Repo"
git remote add origin <repo-url> && git push origin main
```

---

## Architecture

### BigQuery two-layer design

| Layer | Dataset | Table | Purpose |
|---|---|---|---|
| Silver | `mccontext_silver` | `fact_cases` | Row-level support case facts; source of truth for case counts, SLA timings, refund amounts |
| Gold | `mccontext_gold` | `customer_360` | Pre-aggregated customer profile; `open_case_count` and `lifetime_case_count` are denormalized from `fact_cases` at load time |

**Critical invariant:** `customer_360.open_case_count` must equal the count of `status IN ('open','pending')` rows in `fact_cases` for each `customer_id`. `load_mccontext.py` maintains this by back-filling these counts after generating cases. If you re-run the loader, both tables are always kept in sync. Do not update one table without the other.

### YAML → LookML mapping rules

These rules govern all LookML files. Follow them when adding or modifying views.

| YAML construct | LookML output |
|---|---|
| `dimensions` | `dimension` blocks |
| `time_dimensions` | `dimension_group` (type: time) |
| `measures` with `expr` | `measure` blocks — **no raw SQL**; use declarative `type:` + `filters:` so Looker generates the SQL |
| `filters` | `yesno` dimensions (governed predicates Gemini uses as filter chips) |
| `synonyms` | Appended to `description:` (Conversational Analytics uses these for NL matching) |

The hero pattern for the demo is `open_case_count`:
- YAML: `COUNT(CASE WHEN status IN ('open','pending') THEN 1 END)`
- LookML: `type: count` + `filters: [status: "open,pending"]` — declarative, no raw SQL

### Explore design

`mccontext.model.lkml` defines two explores:

| Explore | Label | Use when |
|---|---|---|
| `customer_support` | "Customer Support 360" | Question combines customer attributes (tier, Plus, LTV) with case facts — this is the primary Gemini entry point |
| `cases_only` | "Support Cases" | Question is purely operational (SLA, queue, intent) without needing customer attributes |

The `customer_support` explore starts from `customer_360` (one side) and left-joins `fact_cases` (many side) on `customer_id`. Gemini is expected to route most NL questions here.

### Synthetic data tunables (`load_mccontext.py:main`)

`n_customers = 500`, `target_cases = 2000`, `random.seed(42)`. Changing the seed breaks determinism. Changing counts is fine — re-run takes ~1 min and is pre-approved (WRITE_TRUNCATE on the two demo tables only).

---

## What you can do for me (the user)

- **Run `gcloud`, `bq`, and Python commands** to execute Phases 1, 2, and pre-validation of LookML (sections 4 and 5.1 of DEMO_PLAN.md).
- **Iterate on the synthetic data** in `bigquery/load_mccontext.py` — change distributions, re-run.
- **Edit LookML files** if I ask for new measures, joins, or descriptions. Keep the YAML→LookML mapping faithful (see the `# Mapping rules` header in `fact_cases.view.lkml`).
- **Push LookML to a Git remote** for Looker to pull from, if I set that up.
- **Use the Atlan MCP** (already configured) to query or update Atlan assets if I ask. Do not push to Atlan without explicit confirmation.

## What you cannot do for me

- Click around the Looker UI (creating the connection in Admin, creating the LookML project from blank, enabling Conversational Analytics chat, running the live Gemini chat during the demo). These are my job.
- Click around the Atlan UI for attaching artifacts to assets. (Use the MCP only if I ask explicitly.)
- The actual customer demo on Friday.

---

## Guardrails (hard rules — do not violate)

1. **Never commit the service-account JSON key.** It lives at `~/looker-mccontext-reader.json`, outside the repo. If you see it staged for commit, stop and tell me. Add `*.json` to `.gitignore` if a git repo is created here.
2. **Ask before destructive BigQuery operations.** `bq rm`, `DROP TABLE`, `DELETE FROM`, `TRUNCATE`, or `WRITE_TRUNCATE` against any table other than the two demo tables (`mccontext_silver.fact_cases`, `mccontext_gold.customer_360`) requires my confirmation. The loader script's WRITE_TRUNCATE on those two tables is pre-approved.
3. **Stop on permission errors — do not try to work around them.** If `gcloud` says I lack `roles/iam.serviceAccountAdmin` or any other role, stop, tell me which role is missing, and wait. Don't switch to a personal account, don't try `--impersonate-service-account`, don't create resources under a different project.
4. **Do not modify the source YAMLs** (`fact_cases.yaml`, `customer_360.yaml`). They represent the Atlan Context Repo state and the demo story depends on showing them unchanged on the left side of the side-by-side.
5. **Do not modify `DEMO_PLAN.md`** unless I ask. If a step in the plan turns out to be wrong, flag it in your response and propose the change; don't auto-apply.
6. **Looker connection name is `bq_mccontext`.** If you ever generate new LookML, use that exact connection name.
7. **Treat the Atlan MCP as read-only by default.** Write operations (create asset, attach artifact, update metadata) require my explicit go-ahead per call, not blanket approval.

---

## How to start a session

When I open Claude Code in this folder and say "start" or "continue", do this:

1. Read `DEMO_PLAN.md` (don't dump it back at me — just absorb it).
2. Run `gcloud auth list` and `gcloud config get-value project` to confirm I'm authenticated against `salesengineering-2022`. If not, ask me to authenticate; do not run `gcloud auth login` yourself.
3. Check whether the BigQuery datasets and tables already exist:
   ```bash
   bq ls salesengineering-2022:mccontext_silver
   bq ls salesengineering-2022:mccontext_gold
   ```
4. Tell me where in the plan we are (e.g. "Phase 1 not yet run" vs. "Phase 1 done, Phase 2 service account exists but Looker connection unverified") and ask what to do next.

## Style preferences

- Be terse. I have a tight timeline.
- No trailing summaries of what you just did — I'll read the output.
- If a command would take more than ~30 seconds, tell me before running it.
- Surface errors immediately, with the exact error text. Don't editorialize.
