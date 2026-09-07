# Agentforce Data Library setup (not deployable metadata)

AdaptAbility's grounding is a Data Cloud–native **Agentforce Data Library (ADL)**, managed
through the `sf agent adl` CLI / Connect API — not a standard Metadata API type. Confirmed:
no `AiAgentScorerDefinition`-style deployable component backs it (checked
`DataObjectSearchIndexConf`, the only metadata type in the org's catalog with a plausibly
related name — zero instances). It cannot be retrieved as source and does not move with a
metadata deploy. This agent has not yet been connected to a target org — create the library
fresh there using the config below (adapted from the reference build this architecture reused).

## Reference build's Data Library shape (adapt developerName/label, everything else transfers)

```json
{
  "developerName": "AdaptAbility_Knowledge",
  "masterLabel": "AdaptAbility Knowledge",
  "sourceType": "KNOWLEDGE",
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
  }
}
```

## Prerequisites in the target org (must exist before creating the library)

1. **Knowledge articles imported and published** — `KnowledgeBulkPublisher.cls` +
   `AdaptAbility_Knowledge_Articles.csv`. The library indexes `PublishStatus = Online`
   articles only.
2. **`Knowledge__kav` custom fields** used as content fields — now captured as source:
   - `force-app/main/default/objects/Knowledge__kav/fields/InternalNotes__c.field-meta.xml`
   - `force-app/main/default/objects/Knowledge__kav/fields/Question__c.field-meta.xml`

   `Summary`, `ArticleNumber`, and `Title` are standard fields — no field metadata needed.

## Recreate in a new org

```bash
sf agent adl create \
  --target-org <newOrg> \
  --name "AdaptAbility Knowledge" \
  --developer-name AdaptAbility_Knowledge \
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

`aiAuthoringBundles/AdaptAbility/AdaptAbility.agent` sets the library id **once**, in the
`knowledge:` block, currently a placeholder:

```agentscript
rag_feature_config_id: "ARFPC_REPLACE_WITH_NEW_DATA_LIBRARY_ID"
```

Replace it with `"ARFPC_<newLibraryId>"` once the library above is created and `READY`. Every
retrieval action elsewhere in the script references this same variable
(`ragFeatureConfigId: string = @knowledge.rag_feature_config_id`) — it is **not** hardcoded
per-action, so this is a single-line change, not every occurrence.

## Relevance threshold (FR2.4 — not part of the ADL config itself)

The Data Library API surfaced above has no relevance-threshold field; if a per-retriever
minimum-relevance cutoff was configured, it lives on the retriever/search-index side of Data
Cloud, not on the library. Not yet confirmed retrievable via any CLI surface — treat as a
manual Setup step to re-verify in the new org rather than assumed to carry over.
