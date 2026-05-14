# General Mills Demo Plan — Atlan Context Repo → LookML

**Demo date:** Friday, 2026-05-15
**Prep time:** ~1 working day (Thursday)
**Demo length:** 10–15 minutes
**Audience:** Mixed — data leaders + analytics engineers at General Mills

---

## 1. The story you are telling

> General Mills has decades of business logic trapped inside on-prem Tableau workbooks. When they migrate to Looker on BigQuery, that logic is at risk of being lost or re-implemented inconsistently.
>
> Atlan crawls the on-prem Tableau, captures every datasource, calculated field, and dashboard, and emits **Context Repo YAML files** — a portable, governed semantic definition.
>
> Those YAMLs are not just documentation. They are **executable semantic specs** that can be projected to any modern semantic layer. We project them into LookML, push to Looker, and ask **Gemini Conversational Analytics** the same questions the Tableau dashboards used to answer — and get the same deterministic numbers, with the definitions governed in Atlan.

### Three things the audience should walk away with

1. **Migration without loss.** Atlan's Context Repo captures the institutional knowledge that lives in Tableau today.
2. **Open, portable semantics.** The same YAML can target LookML today, dbt MetricFlow tomorrow, Cube next year. No vendor lock-in on definitions.
3. **Deterministic NL answers.** Gemini in Looker, grounded in governed LookML, returns the *right* number — not a hallucinated one — because every measure, dimension, and filter has one definition.

---

## 2. What you have already (assets produced for this demo)

All files are in `/Users/hari.rongali/Desktop/Customers/general_mills/`:

| File | Purpose |
|---|---|
| `fact_cases.yaml` | Atlan Context Repo file for support cases (already in workspace) |
| `customer_360.yaml` | Atlan Context Repo file for customer profiles (already in workspace) |
| `lookml/manifest.lkml` | Looker project manifest |
| `lookml/mccontext.model.lkml` | Model file with two explores (`customer_support`, `cases_only`) |
| `lookml/views/fact_cases.view.lkml` | LookML view derived from `fact_cases.yaml` |
| `lookml/views/customer_360.view.lkml` | LookML view derived from `customer_360.yaml` |
| `bigquery/load_mccontext.py` | Python script that creates datasets and loads ~500 customers / ~2000 cases of synthetic data into BigQuery |

These are the artifacts you'll demo. The build steps below get them deployed.

---

## 3. Prerequisites checklist (do these tonight)

- [ ] **GCP access**: confirm you can `gcloud auth login` and reach project `salesengineering-2022`.
- [ ] **GCP roles** on `salesengineering-2022`: BigQuery Data Editor, BigQuery Job User, Service Account Admin, Service Account Key Admin. (If you don't have Service Account Admin, ask your GCP admin to create the service account for you — see Phase 2.)
- [ ] **Looker access**: confirm admin login to `https://atlan.cloud.looker.com/`.
- [ ] **Gemini Conversational Analytics**: confirm it's enabled in this Looker instance. (Admin → Labs, or Admin → Gemini.)
- [ ] **Atlan tenant**: confirm the Tableau-extracted assets and the two YAMLs are already loaded and findable.
- [ ] **Python 3.10+** on your laptop with `pip install google-cloud-bigquery faker --break-system-packages`.

---

## 4. Phase 1 — BigQuery setup (~30 min)

The Looker project will read from BigQuery. We need the data loaded first.

### 4.1 Authenticate

```bash
gcloud auth application-default login
gcloud config set project salesengineering-2022
```

### 4.2 Run the loader

```bash
cd /Users/hari.rongali/Desktop/Customers/general_mills/bigquery
python load_mccontext.py
```

Expected output:
```
[OK] Dataset salesengineering-2022.mccontext_silver ready
[OK] Dataset salesengineering-2022.mccontext_gold ready
[OK] Table salesengineering-2022.mccontext_silver.fact_cases created
[OK] Loaded 2000 rows into salesengineering-2022.mccontext_silver.fact_cases
[OK] Table salesengineering-2022.mccontext_gold.customer_360 created
[OK] Loaded 500 rows into salesengineering-2022.mccontext_gold.customer_360
```

### 4.3 Sanity-check in the BQ console

```sql
-- Should show status counts roughly: closed ~55%, resolved ~25%, open ~8%, pending ~7%, escalated ~5%
SELECT status, COUNT(*) AS n
FROM `salesengineering-2022.mccontext_silver.fact_cases`
GROUP BY 1 ORDER BY n DESC;

-- Should show tier distribution roughly: Bronze 50%, Silver 30%, Gold 15%, Platinum 5%
SELECT loyalty_tier, COUNT(*) AS n
FROM `salesengineering-2022.mccontext_gold.customer_360`
GROUP BY 1 ORDER BY n DESC;

-- Cross-table consistency check — the customer_360.open_case_count should equal
-- the count of open/pending cases in fact_cases for that customer.
SELECT c.customer_id,
       c.open_case_count AS reported,
       COUNT(CASE WHEN f.status IN ('open','pending') THEN 1 END) AS actual
FROM `salesengineering-2022.mccontext_gold.customer_360` c
LEFT JOIN `salesengineering-2022.mccontext_silver.fact_cases` f USING (customer_id)
GROUP BY 1, 2
HAVING reported != actual;
-- Expect: zero rows.
```

---

## 5. Phase 2 — Looker connection to BigQuery (~30 min, this is the risky part)

The Looker instance at `atlan.cloud.looker.com` is in a **different** GCP account than `salesengineering-2022`. The cleanest way to bridge them is a service-account JSON key.

### 5.1 Create a service account in `salesengineering-2022`

```bash
gcloud iam service-accounts create looker-mccontext-reader \
    --display-name="Looker → mccontext BigQuery reader" \
    --project=salesengineering-2022

# Grant least-privilege roles
SA="looker-mccontext-reader@salesengineering-2022.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding salesengineering-2022 \
    --member="serviceAccount:${SA}" --role="roles/bigquery.jobUser"
gcloud projects add-iam-policy-binding salesengineering-2022 \
    --member="serviceAccount:${SA}" --role="roles/bigquery.dataViewer"

# Looker also needs a temp dataset for PDTs (persistent derived tables).
# We will create it now and grant the SA dataEditor on JUST that dataset.
bq --location=US mk -d \
    --description "Looker scratch (PDTs)" \
    salesengineering-2022:looker_scratch
bq update --add_iam_member \
    serviceAccount:${SA}:roles/bigquery.dataEditor \
    salesengineering-2022:looker_scratch

# Generate a JSON key (keep this file safe; you'll upload it to Looker)
gcloud iam service-accounts keys create ~/looker-mccontext-reader.json \
    --iam-account="${SA}"
```

### 5.2 Create the connection in Looker

1. In `https://atlan.cloud.looker.com/`, go to **Admin → Connections → Add Connection**.
2. **Name:** `bq_mccontext`  ← must match `connection: "bq_mccontext"` in `mccontext.model.lkml`.
3. **Dialect:** `Google BigQuery Standard SQL`
4. **Project Name:** `salesengineering-2022`
5. **Dataset:** `mccontext_gold` (any dataset that exists; Looker just uses it for default qualification)
6. **Service Account Email:** the SA email from above
7. **Service Account JSON/P12 File:** upload `~/looker-mccontext-reader.json`
8. **Persistent Derived Table (PDT) settings:**
   - Temp Dataset: `looker_scratch`
   - Enable PDTs: yes
9. Click **Test these settings**. All checks should be green. If they're not, see Risk #1 below.
10. **Connect**.

---

## 6. Phase 3 — Create the LookML project and push files (~30 min)

### 6.1 Create the project

1. In Looker, **Develop → Manage LookML Projects → New LookML Project**.
2. **Project Name:** `mccontext_demo`
3. **Starting Point:** *Blank Project*
4. **Connection:** `bq_mccontext`

### 6.2 Enable Development Mode

Top-right toggle. Turn it **ON**.

### 6.3 Add the files

Easiest way for Friday: drag-and-drop in the Looker IDE.

1. In the project file tree, delete any placeholder files Looker generated.
2. Create a folder `views/` (right-click → Create Folder).
3. Upload (or copy-paste contents from your local files):
   - `manifest.lkml` → root
   - `mccontext.model.lkml` → root
   - `views/fact_cases.view.lkml`
   - `views/customer_360.view.lkml`

Alternative — push via Git (recommended if you have time):
1. **Configure Git** in Looker project settings, point at a bare GitHub repo you own.
2. From your laptop:
   ```bash
   cd /Users/hari.rongali/Desktop/Customers/general_mills/lookml
   git init && git add . && git commit -m "Initial LookML from Atlan Context Repo"
   git remote add origin <repo-url> && git push origin main
   ```
3. In Looker, **Pull from Production** → **Deploy to Production**.

### 6.4 Validate

In the project, click **Validate LookML**. Fix any errors (most likely cause: wrong connection name or wrong fully-qualified table name).

### 6.5 Deploy

Click **Deploy to Production** (or the rocket icon).

### 6.6 Smoke test the Explore

1. **Explore → Customer Support 360**.
2. Pick `Customer 360 → Loyalty Tier` as a dimension.
3. Pick `Customer 360 → Customer Count` as a measure.
4. Run. You should see 4 rows: Bronze, Silver, Gold, Platinum with realistic counts.

If that works, the pipeline is live.

---

## 7. Phase 4 — Enable Conversational Analytics on the model (~15 min)

> Note: the exact UI varies by Looker release. Check Admin → Gemini and Admin → Labs.

1. **Admin → Gemini → Conversational Analytics** → enable on the `mccontext_demo` model (or on the `customer_support` explore specifically).
2. From the explore page, you should see a **chat / "Ask"** button in the top-right.
3. Ask a warm-up question to confirm it's working:
   - *"How many customers do we have by loyalty tier?"*
   - Expected: a bar chart with Bronze ~250, Silver ~150, Gold ~75, Platinum ~25.

---

## 8. Phase 5 — Pre-stage Atlan (~15 min)

You said the Tableau assets are already in Atlan. Two extra touches that will make the demo land:

1. **Attach the YAML files as artifacts** on the corresponding Atlan asset pages (the support-case and customer-360 datasources). Title them "Context Repo — fact_cases.yaml" and "Context Repo — customer_360.yaml".
2. **Add a README on each asset** that says something like: *"This Atlan context was extracted from on-prem Tableau workbook `Customer Care 360.twbx`. The YAML below is the portable, governed semantic definition. Projected to LookML for the GCP/Looker migration. See `mccontext.model.lkml` in the Looker `mccontext_demo` project."*

This is what sells the migration story without you having to narrate it.

---

## 9. The side-by-side moment (this is the technical credibility beat)

Open **two Sublime windows side-by-side** (or one with split panes):

**Left pane:** `fact_cases.yaml` lines 99–102

```yaml
- name: open_case_count
  description: Number of currently open/pending cases
  expr: COUNT(CASE WHEN status IN ('open', 'pending') THEN 1 END)
  data_type: NUMBER
```

**Right pane:** `fact_cases.view.lkml` (around the `# HERO METRIC` comment)

```lookml
measure: open_case_count {
  type: count
  description: "Number of currently open/pending cases."
  filters: [status: "open,pending"]
}
```

### What to say

> "On the left is the Tableau-era definition that Atlan captured — written once, in YAML, governed in the Context Repo. On the right is the LookML our converter generates. Notice three things:
>
> 1. **No raw SQL in LookML** — the filtered count is declarative, so the Looker query engine builds the correct SQL against whatever physical schema lives in BigQuery.
> 2. **One source of truth** — if the definition of 'open' ever changes from `('open','pending')` to also include `'on_hold'`, we change one line in Atlan and re-project. No hunting through workbooks.
> 3. **Gemini can answer questions about 'open cases' deterministically**, because there's exactly one governed measure called `open_case_count`, with a description and synonyms the LLM is grounded on."

### Also show the filter translation

**YAML:**
```yaml
- name: at_risk_customers
  description: Customers with low CSAT (below 3.0)
  expr: avg_csat_last_5 < 3.0
```

**LookML:**
```lookml
dimension: is_at_risk {
  type: yesno
  sql: ${TABLE}.avg_csat_last_5 < 3.0 ;;
  description: "Customers with low CSAT (below 3.0)."
}
```

> "Tableau set filters become governed yesno dimensions. Gemini can now answer 'how many at-risk customers do we have?' without hallucinating the threshold."

---

## 10. The demo script (10–15 min, minute-by-minute)

| Time | Beat | What's on screen | What you say |
|---|---|---|---|
| 0:00 | **Hook** | Atlan tenant, Tableau-sourced asset page | "General Mills has thousands of these. Each one has logic in it that nobody wrote down anywhere else." |
| 1:30 | **Atlan captured it** | Atlan asset → lineage to Tableau, then YAML artifact | "Atlan crawled the on-prem Tableau and emitted this — a Context Repo YAML. Portable, governed, version-controlled." |
| 3:00 | **The YAML** | Sublime, `fact_cases.yaml` open | "Dimensions, time dimensions, measures, named filters, synonyms. This is the semantic model of one Tableau workbook, in 145 lines of YAML." |
| 4:30 | **The side-by-side** | Split pane: YAML + LookML hero measure | (Script above — the `open_case_count` walkthrough.) |
| 6:30 | **In Looker** | Looker IDE showing the deployed project | "Same definition, projected to LookML. Looker is now wired to BigQuery on GCP." |
| 7:30 | **Explore** | Customer Support 360 explore — drag in Loyalty Tier × Avg CSAT, then add `is_at_risk`=Yes | "Notice the governed filter — same definition the Tableau workbook had." |
| 9:00 | **Conversational Analytics** | Gemini chat panel in Looker | Ask: *"How many open cases do we have by team, and which team has the worst time to resolution?"* |
| 10:30 | **Same Q twice** | Same chat, follow-up | *"Now filter to just Plus subscribers."* — Gemini composes a query that joins fact_cases to customer_360 using the governed explore. |
| 12:00 | **Land the punchline** | Back to Atlan | "If General Mills changes the definition of 'open' tomorrow — say, to include 'on_hold' — they change one line in Atlan, regenerate LookML, and every Looker dashboard *and* every Gemini answer stays in sync. That's the migration without loss." |
| 13:30 | **Q&A** | — | — |

---

## 11. NL questions to ask Gemini (rehearse all five — pick 2 live)

| # | Question | Why it works | Expected answer shape |
|---|---|---|---|
| 1 | "How many cases do we have by status?" | Warm-up. Single view, single dimension. | Bar chart, 5 bars. |
| 2 | "Show the average time to resolution in hours by team, for resolved and closed cases." | Hits a derived measure with a status filter. (Filtering to resolved/closed avoids NULL TTR on open cases.) | Bar chart, 5 teams. |
| 3 | "Which Platinum customers have open cases right now?" | Uses the join + governed `is_platinum_tier` and `has_open_cases` filters. | Small list of names. |
| 4 | "What's the average CSAT by loyalty tier for Plus subscribers?" | Tests join + governed predicate (`is_plus_subscriber`) and exercises the avg_csat measure cleanly. | 4 rows, ascending by tier. |
| 5 | "Which intent type generates the most refund dollars?" | Aggregation + grouping; closing-the-loop story. | `double_charge` / `refund_request` near top. |

**If Gemini stumbles** on the exact wording, paste a hint: *"Use the customer_support explore."* That's a teaching moment about how the governed model helps the LLM choose the right surface area.

---

## 12. Risk register & fallbacks

| # | Risk | Likelihood | Mitigation / Backup |
|---|---|---|---|
| 1 | **Looker can't connect to BigQuery** (cross-account auth) | Medium | Use the SA-key flow in §5.1 exactly. If it fails, the SA likely doesn't have IAM access to the `looker_scratch` dataset. Re-run the `bq update --add_iam_member` line. As a last resort, switch Looker connection to "Symmetric Aggregates: off" and disable PDTs. |
| 2 | **Gemini Conversational Analytics not available on the instance** | Medium | Check Admin → Gemini. If it's not on, you can still demo with manual Explore drag-and-drop and **call out** the same point about governed semantics. Pre-record a 2-minute Gemini interaction the night before as a backup video. |
| 3 | **LookML validation fails** | Low-medium | Re-read error in IDE. Most common: connection name mismatch or backticked BQ table name. The view files use `salesengineering-2022.mccontext_silver.fact_cases` — confirm those datasets exist (see §4.3). |
| 4 | **Synthetic data doesn't produce interesting answers** | Low | The loader uses `random.seed(42)` so it's deterministic. If a particular question lands flat, tweak `n_customers` / `target_cases` and rerun — takes ~1 min. |
| 5 | **General Mills asks "but this is McContext, not General Mills data"** | Medium | Have an honest answer ready: *"Right — this is a sample dataset that demonstrates the YAML-to-LookML mechanic. The same converter runs against any Atlan Context Repo. If you point us at one of your real Tableau workbooks, we'll show you the equivalent on your data in a week."* |
| 6 | **Live Looker is slow during demo** | Low | Pre-run each NL question 5 minutes before the demo so query results are cached. |

---

## 13. Open question for you to decide tomorrow morning

**Do you want me to also produce a one-page leave-behind PDF** that summarizes the YAML→LookML translation table (which YAML construct maps to which LookML construct) so General Mills's analytics engineers can take it home? It's ~30 minutes of extra work and pairs naturally with the demo.

---

## 14. Day-of (Friday) checklist — run this 30 minutes before the meeting

- [ ] Looker development mode OFF, production deployed
- [ ] Pre-run all 5 NL questions in Conversational Analytics
- [ ] Open in tabs (left to right): Atlan asset page, Sublime with YAML+LookML side-by-side, Looker IDE, Looker Explore with chat panel
- [ ] Disable laptop notifications (Slack, calendar)
- [ ] Screen-share resolution sanity-checked (font size in Sublime ≥ 14pt)
- [ ] Backup screenshot folder open in Finder, just in case
