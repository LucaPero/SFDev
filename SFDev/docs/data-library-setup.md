# Agentforce Data Library setup (not deployable metadata)

Ask Nimbus's grounding is a Data Cloud–native **Agentforce Data Library (ADL)**, managed
through the `sf agent adl` CLI / Connect API — not a standard Metadata API type. Confirmed:
no `AiAgentScorerDefinition`-style deployable component backs it (checked
`DataObjectSearchIndexConf`, the only metadata type in the org's catalog with a plausibly
related name — zero instances). It cannot be retrieved as source and does not move with a
metadata deploy. Recreate it explicitly in any new org using the config captured below.

## Current org's Data Library (source of truth, captured via `sf agent adl get`)

```json
{
  "developerName": "Ask_Nimbus_Knowledge",
  "masterLabel": "Ask Nimbus Knowledge",
  "libraryId": "1JDaj00000MT7PdGAL",
  "sourceType": "KNOWLEDGE",
  "status": "READY",
  "featureAssignments": ["SERVICE_REPLIES"],
  "groundingSource": {
    "groundingSourceType": "KNOWLEDGE",
    "knowledgeConfig": {
      "contentFields": ["Summary", "InternalNotes__c", "Question__c"],
      "primaryIndexField1": "ArticleNumber",
      "primaryIndexField2": "Title",
      "isDataCategoryRuleEnabled": false,
      "isRestrictToPublicArticle": false
    }
  },
  "retriever": { "id": "1Cxaj000000WCVtCAO", "label": "KA_Ask_Nimbus_Knowledge" }
}
```

## Prerequisites in the target org (must exist before creating the library)

1. **Knowledge articles imported and published** — `KnowledgeBulkPublisher.cls` +
   `Nimbus_Knowledge_Articles.csv` (or whatever the renamed/re-themed article set becomes).
   The library indexes `PublishStatus = Online` articles only.
2. **`Knowledge__kav` custom fields** used as content fields — now captured as source:
   - `force-app/main/default/objects/Knowledge__kav/fields/InternalNotes__c.field-meta.xml`
   - `force-app/main/default/objects/Knowledge__kav/fields/Question__c.field-meta.xml`

   `Summary`, `ArticleNumber`, and `Title` are standard fields — no field metadata needed.

## Recreate in a new org

```bash
sf agent adl create \
  --target-org <newOrg> \
  --name "Ask Nimbus Knowledge" \
  --developer-name Ask_Nimbus_Knowledge \
  --source-type knowledge \
  --primary-index-field1 ArticleNumber \
  --primary-index-field2 Title \
  --content-fields "Summary,InternalNotes__c,Question__c" \
  --wait 10
```

`--primary-index-field1`/`2` are **immutable after creation** — get them right the first time.
`--content-fields` can be changed later via `sf agent adl update` (triggers re-indexing).

This provisions the full Data Cloud pipeline (Data Stream → DLO → DMO → Search Index →
Retriever) and returns a **new** `libraryId` (prefix `1JD`) — confirm via:

```bash
sf agent adl get --library-id <newLibraryId> --target-org <newOrg>
sf agent adl status --library-id <newLibraryId> --target-org <newOrg>
```

Wait for `"status": "READY"` before wiring the agent — grounding calls against a still-indexing
library fail or return empty.

## Wiring it into the Agent Script (the one line that must change per org)

`aiAuthoringBundles/<agent>/<agent>.agent` sets the library id **once**, in the `knowledge:`
block:

```agentscript
rag_feature_config_id: "ARFPC_<libraryId>"
```

Every retrieval action elsewhere in the script references this same variable
(`ragFeatureConfigId: string = @knowledge.rag_feature_config_id`) — it is **not** hardcoded
per-action, so moving orgs only requires updating this single line to
`"ARFPC_<newLibraryId>"`, not every occurrence.

## Relevance threshold (FR2.4 — not part of the ADL config itself)

The Data Library API surfaced above has no relevance-threshold field; if a per-retriever
minimum-relevance cutoff was configured, it lives on the retriever/search-index side of Data
Cloud, not on the library. Not yet confirmed retrievable via any CLI surface — treat as a
manual Setup step to re-verify in the new org rather than assumed to carry over.
