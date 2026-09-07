// Quick check after running run-publish-batch.apex — confirms how many articles
// are Online vs. still Draft. Run with: sf apex run --file scripts/check-publish-status.apex
Integer online = [SELECT COUNT() FROM Knowledge__kav WHERE PublishStatus = 'Online' AND Language = 'en_US'];
Integer draft = [SELECT COUNT() FROM Knowledge__kav WHERE PublishStatus = 'Draft' AND Language = 'en_US'];
System.debug('Online: ' + online + ' | Draft: ' + draft);
