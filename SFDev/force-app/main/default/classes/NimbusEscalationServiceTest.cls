@isTest
private class NimbusEscalationServiceTest {

    private static NimbusEscalationService.Request buildRequest(String sessionId, String reasonCode) {
        NimbusEscalationService.Request req = new NimbusEscalationService.Request();
        req.sessionId = sessionId;
        req.reasonCode = reasonCode;
        req.intentSummary = 'Wants to dispute a duplicate charge on this month\'s invoice.';
        req.transcript = 'User: why was I charged twice?\nAgent: here are the documented causes...';
        req.sentimentTrend = 'flat';
        req.articlesServed = 'ka0aj000002PBVRAA4';
        req.queueHint = 'Billing';
        return req;
    }

    @isTest
    static void createsOneCaseAsBackgroundRecordAndResolvesBillingQueueName() {
        NimbusEscalationService.Request req = buildRequest('session-001', 'account_specific');

        Test.startTest();
        List<NimbusEscalationService.Result> results =
            NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].isSuccess, 'Expected escalation to succeed: ' + results[0].errorMessage);
        System.assertNotEquals(null, results[0].caseId);

        Case created = [
            SELECT Nimbus_Session_Id__c, Escalation_Reason_Code__c, OwnerId, Resolved_Queue_Name__c
            FROM Case
            WHERE Id = :results[0].caseId
        ];
        System.assertEquals('session-001', created.Nimbus_Session_Id__c);
        System.assertEquals('account_specific', created.Escalation_Reason_Code__c);
        System.assertEquals('Nimbus_Billing', created.Resolved_Queue_Name__c,
            'The domain queue name should be recorded for the live-chat flow even though the Case itself is not owned by that queue.');

        Group holdingQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Nimbus_Case_Records'];
        System.assertEquals(holdingQueue.Id, created.OwnerId,
            'The Case must be owned by the non-routed holding queue so it never triggers an automatic Omni-Channel push.');
    }

    @isTest
    static void duplicateTriggerInSameSessionUpdatesSameCase() {
        NimbusEscalationService.Request first = buildRequest('session-002', 'unresolved_after_3_turns');
        NimbusEscalationService.Request retry = buildRequest('session-002', 'unresolved_after_3_turns');
        retry.intentSummary = 'Updated summary after a second turn.';

        Test.startTest();
        NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ first });
        NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ retry });
        Test.stopTest();

        List<Case> cases = [SELECT Id, Intent_Summary__c FROM Case WHERE Nimbus_Session_Id__c = 'session-002'];
        System.assertEquals(1, cases.size(), 'A repeated escalation trigger in the same session must not open a second Case.');
        System.assertEquals('Updated summary after a second turn.', cases[0].Intent_Summary__c);
    }

    @isTest
    static void securityKeywordAlwaysResolvesLegalTrustQueueNameRegardlessOfQueueHint() {
        NimbusEscalationService.Request req = buildRequest('session-003', 'security_keyword');
        req.queueHint = 'Technical'; // deliberately wrong hint to prove the override wins

        Test.startTest();
        List<NimbusEscalationService.Result> results =
            NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ req });
        Test.stopTest();

        System.assert(results[0].isSuccess, results[0].errorMessage);
        Case created = [SELECT OwnerId, Resolved_Queue_Name__c FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals('Nimbus_LegalTrust', created.Resolved_Queue_Name__c);

        Group holdingQueue = [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Nimbus_Case_Records'];
        System.assertEquals(holdingQueue.Id, created.OwnerId);
    }

    @isTest
    static void missingRequiredFieldFailsWithoutCreatingACase() {
        NimbusEscalationService.Request req = buildRequest('session-004', 'human_request');
        req.intentSummary = null;

        Test.startTest();
        List<NimbusEscalationService.Result> results =
            NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage.contains('intentSummary'));
        System.assertEquals(0, [SELECT COUNT() FROM Case WHERE Nimbus_Session_Id__c = 'session-004']);
    }

    @isTest
    static void invalidReasonCodeIsRejected() {
        NimbusEscalationService.Request req = buildRequest('session-005', 'made_up_reason');

        Test.startTest();
        List<NimbusEscalationService.Result> results =
            NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage.contains('reasonCode'));
    }

    @isTest
    static void bulkRequestsAcrossMultipleSessionsEachProduceOneCase() {
        List<NimbusEscalationService.Request> requests = new List<NimbusEscalationService.Request>{
            buildRequest('session-006', 'no_confident_answer'),
            buildRequest('session-007', 'service_degraded'),
            buildRequest('session-008', 'gdpr_request')
        };

        Test.startTest();
        List<NimbusEscalationService.Result> results = NimbusEscalationService.escalateToHuman(requests);
        Test.stopTest();

        System.assertEquals(3, results.size());
        for (NimbusEscalationService.Result r : results) {
            System.assert(r.isSuccess, r.errorMessage);
        }
        System.assertEquals(3, [SELECT COUNT() FROM Case WHERE Nimbus_Session_Id__c IN ('session-006', 'session-007', 'session-008')]);
    }
}
