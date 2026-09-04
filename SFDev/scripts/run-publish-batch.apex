// Kicks off KnowledgeBulkPublisher after the CSV import.
// Run with: sf apex run --file scripts/run-publish-batch.apex --target-org <alias>
Id jobId = Database.executeBatch(new KnowledgeBulkPublisher(), 50);
System.debug('KnowledgeBulkPublisher batch job submitted: ' + jobId);
