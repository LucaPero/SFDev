@isTest
private class AdaptAbilityEscalationServiceTest {

    private static AdaptAbilityEscalationService.Request buildRequest(String sessionId, String reasonCode) {
        AdaptAbilityEscalationService.Request req = new AdaptAbilityEscalationService.Request();
        req.sessionId = sessionId;
        req.reasonCode = reasonCode;
        req.intentSummary = 'Wants to request an ergonomic keyboard and a sit-stand desk.';
        req.transcript = 'User: what accommodations are available for wrist pain?\nAgent: here are the documented options...';
        req.sentimentTrend = 'flat';
        req.articlesServed = 'ka0aj000002PBVRAA4';
        req.queueHint = 'Accommodations';
        return req;
    }

    @isTest
    static void createsOneCaseAsBackgroundRecordAndResolvesAccommodationsQueueName() {
        AdaptAbilityEscalationService.Request req = buildRequest('session-001', 'employee_specific_case_data');

        Test.startTest();
        List<AdaptAbilityEscalationService.Result> results =
            AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].isSuccess, 'Expected escalation to succeed: ' + results[0].errorMessage);
        System.assertNotEquals(null, results[0].caseId);

        Case created = [
            SELECT AdaptAbility_Session_Id__c, Escalation_Reason_Code__c, OwnerId, Resolved_Queue_Name__c, CaseNumber
            FROM Case
            WHERE Id = :results[0].caseId
        ];
        System.assertEquals(created.CaseNumber, results[0].caseNumber,
            'The Result must carry back the human-readable case number so the agent can hand it to the requester as a tracking reference.');
        System.assertEquals('session-001', created.AdaptAbility_Session_Id__c);
        System.assertEquals('employee_specific_case_data', created.Escalation_Reason_Code__c);
        System.assertEquals('AdaptAbility_Accommodations', created.Resolved_Queue_Name__c,
            'The domain queue name should be recorded for the live-chat flow even though the Case itself is not owned by that queue.');

        Group holdingQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'AdaptAbility_Case_Records'];
        System.assertEquals(holdingQueue.Id, created.OwnerId,
            'The Case must be owned by the non-routed holding queue so it never triggers an automatic Omni-Channel push.');
    }

    @isTest
    static void duplicateTriggerInSameSessionUpdatesSameCase() {
        AdaptAbilityEscalationService.Request first = buildRequest('session-002', 'unresolved_after_3_turns');
        AdaptAbilityEscalationService.Request retry = buildRequest('session-002', 'unresolved_after_3_turns');
        retry.intentSummary = 'Updated summary after a second turn.';

        Test.startTest();
        AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ first });
        AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ retry });
        Test.stopTest();

        List<Case> cases = [SELECT Id, Intent_Summary__c FROM Case WHERE AdaptAbility_Session_Id__c = 'session-002'];
        System.assertEquals(1, cases.size(), 'A repeated escalation trigger in the same session must not open a second Case.');
        System.assertEquals('Updated summary after a second turn.', cases[0].Intent_Summary__c);
    }

    @isTest
    static void privacyConcernAlwaysResolvesPrivacyLegalQueueNameRegardlessOfQueueHint() {
        AdaptAbilityEscalationService.Request req = buildRequest('session-003', 'privacy_concern');
        req.queueHint = 'CustomerAccess'; // deliberately wrong hint to prove the override wins

        Test.startTest();
        List<AdaptAbilityEscalationService.Result> results =
            AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ req });
        Test.stopTest();

        System.assert(results[0].isSuccess, results[0].errorMessage);
        Case created = [SELECT OwnerId, Resolved_Queue_Name__c FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals('AdaptAbility_PrivacyLegal', created.Resolved_Queue_Name__c);

        Group holdingQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'AdaptAbility_Case_Records'];
        System.assertEquals(holdingQueue.Id, created.OwnerId);
    }

    @isTest
    static void missingRequiredFieldFailsWithoutCreatingACase() {
        AdaptAbilityEscalationService.Request req = buildRequest('session-004', 'human_request');
        req.intentSummary = null;

        Test.startTest();
        List<AdaptAbilityEscalationService.Result> results =
            AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage.contains('intentSummary'));
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE AdaptAbility_Session_Id__c = 'session-004']);
    }

    @isTest
    static void invalidReasonCodeIsRejected() {
        AdaptAbilityEscalationService.Request req = buildRequest('session-005', 'made_up_reason');

        Test.startTest();
        List<AdaptAbilityEscalationService.Result> results =
            AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage.contains('reasonCode'));
    }

    @isTest
    static void bulkRequestsAcrossMultipleSessionsEachProduceOneCase() {
        List<AdaptAbilityEscalationService.Request> requests = new List<AdaptAbilityEscalationService.Request>{
            buildRequest('session-006', 'no_confident_answer'),
            buildRequest('session-007', 'service_degraded'),
            buildRequest('session-008', 'data_privacy_request')
        };

        Test.startTest();
        List<AdaptAbilityEscalationService.Result> results = AdaptAbilityEscalationService.escalateToHuman(requests);
        Test.stopTest();

        System.assertEquals(3, results.size());
        for (AdaptAbilityEscalationService.Result r : results) {
            System.assert(r.isSuccess, r.errorMessage);
        }
        System.assertEquals(3, [SELECT COUNT() FROM Case WHERE AdaptAbility_Session_Id__c IN ('session-006', 'session-007', 'session-008')]);
    }

    @isTest
    static void failedRetrievalApologyIsNotStoredAsAServedArticle() {
        AdaptAbilityEscalationService.Request req = buildRequest('session-010', 'no_confident_answer');
        req.articlesServed = 'Sorry, I can\'t find an answer based on the available articles.';

        Test.startTest();
        List<AdaptAbilityEscalationService.Result> results =
            AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ req });
        Test.stopTest();

        System.assert(results[0].isSuccess, results[0].errorMessage);
        Case created = [SELECT Knowledge_Articles_Served__c FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals('none', created.Knowledge_Articles_Served__c,
            'A failed-retrieval apology captured verbatim from knowledgeSummary must not be stored as if it were a served article.');
    }

    @isTest
    static void urgentDeadlineOrSafetyResolvesAccommodationsQueueByDefault() {
        AdaptAbilityEscalationService.Request req = buildRequest('session-009', 'urgent_deadline_or_safety');

        Test.startTest();
        List<AdaptAbilityEscalationService.Result> results =
            AdaptAbilityEscalationService.escalateToHuman(new List<AdaptAbilityEscalationService.Request>{ req });
        Test.stopTest();

        System.assert(results[0].isSuccess, results[0].errorMessage);
        Case created = [SELECT Resolved_Queue_Name__c FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals('AdaptAbility_Accommodations', created.Resolved_Queue_Name__c,
            'A non-privacy urgent trigger should still resolve via the normal queueHint, not force Privacy/Legal.');
    }
}
