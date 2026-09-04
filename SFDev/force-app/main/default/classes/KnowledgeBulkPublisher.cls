/**
 * One-time workshop utility: publishes every Draft Knowledge__kav article (en_US)
 * left behind by the CSV data import, since KbManagement.PublishingService.publishArticle
 * is not bulkified and must be looped per master KnowledgeArticleId.
 * Run with: Database.executeBatch(new KnowledgeBulkPublisher(), 50);
 */
public class KnowledgeBulkPublisher implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, KnowledgeArticleId
            FROM Knowledge__kav
            WHERE PublishStatus = 'Draft' AND Language = 'en_US'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Knowledge__kav> scope) {
        Set<Id> alreadyPublished = new Set<Id>();
        for (Knowledge__kav kav : scope) {
            if (!alreadyPublished.contains(kav.KnowledgeArticleId)) {
                KbManagement.PublishingService.publishArticle(kav.KnowledgeArticleId, false);
                alreadyPublished.add(kav.KnowledgeArticleId);
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Integer remainingDrafts = [
            SELECT COUNT()
            FROM Knowledge__kav
            WHERE PublishStatus = 'Draft' AND Language = 'en_US'
        ];
        System.debug('KnowledgeBulkPublisher finished. Remaining drafts: ' + remainingDrafts);
    }
}
