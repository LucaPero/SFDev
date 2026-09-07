# AdaptAbility — Everline Knowledge Articles — Deployment Guide

67 Salesforce Knowledge article records for AdaptAbility, an Agentforce for Good hackathon
submission combining the Abilityforce and Neuroforce challenge themes: a deterministic
RAG-grounded agent serving both employees and customers of Everline (a fictional workplace
collaboration SaaS company), covering 8 domains split across an employee track (Workplace
Accommodations & Assistive Technology, Flexible Work Arrangements, Leave & Benefits, Manager &
Team Enablement) and a customer track (Product Accessibility Features, Customer Accommodation
Requests), plus two shared domains (Accommodation Policy/Privacy/Rights, Troubleshooting).

**Only standard Knowledge fields are used** — no custom fields, no custom Article Types.
Records import into the default `Knowledge__kav` object that Salesforce creates automatically
the moment Knowledge is enabled in an org.

| File | Purpose |
|---|---|
| `AdaptAbility_Knowledge_Articles.csv` | The 67 article records (Title, UrlName, Summary, Language, IsVisibleInPkb, IsVisibleInCsp, IsVisibleInPrm). |
| `scripts/generate-articles.js` | The generator that produced the CSV — rerun with `node scripts/generate-articles.js` if you edit the content. |
| `force-app/main/default/classes/KnowledgeBulkPublisher.cls` | Batch Apex that publishes every Draft article after import (see why below). |
| `scripts/run-publish-batch.apex` | One-liner that kicks off the batch job. |
| `scripts/check-publish-status.apex` | Confirms how many articles are Online vs. still Draft. |

## Why a separate publish step is needed

Inserting a Knowledge record always creates it as a **Draft** — there's no way to insert
directly as `Online` via the API or Data Loader. Salesforce's supported way to publish is the
Apex method `KbManagement.PublishingService.publishArticle()`, and it **isn't bulkified**, so
a plain loop in one transaction risks hitting governor limits at any real scale.
`KnowledgeBulkPublisher` handles this safely as a Batch Apex job (chunks of 50).

## Prerequisites

1. **Salesforce Knowledge must be enabled** in the target org: Setup → Quick Find → *Knowledge Settings* → Enable, if not already on. This auto-creates the `Knowledge__kav` object with the standard fields this CSV uses.
2. **Salesforce CLI (`sf`)** installed and authenticated to the target org (`sf org login web --alias adaptabilityOrg`).
3. A user with **Manage Knowledge** permission (Knowledge User checkbox + appropriate permission set).

## Step 1 — Import the 67 articles

Using the Salesforce CLI (Bulk API 2.0):

```bash
sf data import bulk --sobject Knowledge__kav --file AdaptAbility_Knowledge_Articles.csv --target-org adaptabilityOrg --wait 10
```

**Or**, if you'd rather use Data Loader:
1. Open Data Loader → **Insert**.
2. Object: `Knowledge__kav` ("Knowledge").
3. CSV file: `AdaptAbility_Knowledge_Articles.csv`.
4. Map all 7 columns 1:1 (they already match the standard field API names).
5. Run the insert.

All 67 records land as **Draft**, `Language = en_US`.

## Step 2 — Deploy and run the publish batch

Deploy the Apex class from this folder (it's a self-contained SFDX project — `sfdx-project.json` is already set up):

```bash
sf project deploy start --source-dir force-app --target-org adaptabilityOrg
```

Kick off the batch publish job:

```bash
sf apex run --file scripts/run-publish-batch.apex --target-org adaptabilityOrg
```

Batch jobs run asynchronously — give it a minute, then confirm:

```bash
sf apex run --file scripts/check-publish-status.apex --target-org adaptabilityOrg
```

You're looking for `Online: 67 | Draft: 0`. If any remain in Draft, just rerun
`run-publish-batch.apex` — it only targets records still in Draft, so it's safe to repeat.

## Step 3 — Verify in the org

Setup → Quick Find → **Knowledge Articles** (or the Knowledge tab) should now list all 67
articles, Online, organized across the 8 domains. From here, follow
`docs/data-library-setup.md` to create the Agentforce Data Library and wire the agent's
`rag_feature_config_id` to it (this is not deployable metadata and must be done per-org).

## Notes & caveats

- **Re-running the import**: `UrlName` must be unique, so re-importing the same CSV a second
  time will fail on duplicate `UrlName` values rather than silently double-creating articles —
  that's intentional, not a bug to work around.
- **Multiple Article Types / Record Types**: if your org already has custom Knowledge Article
  Types configured from prior work, confirm `Knowledge__kav` is still the intended target and
  that your running user's default Knowledge record type is what you expect — the CSV doesn't
  set `RecordTypeId`, so it relies on the org's default.
- **Visibility flags are set per-domain, not uniformly**: employee-track articles
  (Accommodations, Flexible Work, Leave & Benefits, Manager Enablement) are
  `IsVisibleInPkb=TRUE, IsVisibleInCsp=FALSE`; customer-track articles (Product Accessibility,
  Customer Accommodation Requests) are the reverse; the two shared domains (Policy/Privacy/
  Rights, Troubleshooting) are visible in both. `IsVisibleInPrm` is `FALSE` throughout (no
  partner community). This split is what keeps the employee and customer tracks from leaking
  into each other's grounding — adjust in `scripts/generate-articles.js`'s
  `VISIBILITY_BY_AUDIENCE` map, not by hand-editing the CSV, if you change it.
- **Content is intentionally fictional**: it's written specifically to match the Everline case
  study (accommodation policy, leave process, product accessibility features, etc.) so it lines
  up with the example utterances and test cases in `AdaptAbility-AgentSpec.md` and
  `tests/AdaptAbility-testing-center.yaml` — don't expect it to reflect a real company's actual
  policies.
