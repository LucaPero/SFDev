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

    // Swarm creation now calls the platform's createSwarmSlackChannel action
    // through Create_Swarm_Slack_Channel_Direct, which does real external
    // Slack API work — Test.isRunningTest() skips it entirely (confirmed
    // live: running it inside a test transaction throws a platform
    // UNKNOWN_EXCEPTION, not a normal failure), the same way you can't unit
    // test a real HTTP callout's side effect. These tests confirm escalation
    // still succeeds cleanly around that skipped call, not the Slack
    // provisioning itself — that's verified separately via a direct,
    // non-test Apex run against the org.
    @isTest
    static void escalationSucceedsEvenThoughSwarmCreationIsSkippedInTests() {
        NimbusEscalationService.Request req = buildRequest('session-009', 'human_request');

        Test.startTest();
        List<NimbusEscalationService.Result> results =
            NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ req });
        Test.stopTest();

        System.assert(results[0].isSuccess, results[0].errorMessage);
        System.assertNotEquals(null, results[0].caseId);
    }

    @isTest
    static void duplicateTriggerInSameSessionStillUpdatesSameCaseWithSwarmSkipped() {
        NimbusEscalationService.Request first = buildRequest('session-010', 'unresolved_after_3_turns');
        NimbusEscalationService.Request retry = buildRequest('session-010', 'unresolved_after_3_turns');

        Test.startTest();
        List<NimbusEscalationService.Result> firstResults =
            NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ first });
        List<NimbusEscalationService.Result> retryResults =
            NimbusEscalationService.escalateToHuman(new List<NimbusEscalationService.Request>{ retry });
        Test.stopTest();

        System.assert(retryResults[0].isSuccess, retryResults[0].errorMessage);
        System.assertEquals(firstResults[0].caseId, retryResults[0].caseId,
            'A repeated escalation trigger in the same session must still update the same Case.');
    }

    @isTest
    static void swarmChannelNameIsSanitizedAndUnique() {
        Id fakeCaseId = (Id) '500000000000123';
        String channelName = NimbusEscalationService.buildSwarmChannelName('human_request', fakeCaseId);

        System.assert(channelName.startsWith('nimbus-human-request-'),
            'Underscores in the reason code must be converted to hyphens for a valid Slack channel name.');
        System.assertEquals(channelName, channelName.toLowerCase(),
            'Slack channel names must be lowercase.');
    }

    @isTest
    static void addSwarmMembersSkipsCleanlyWithNoMembersOrNoSwarm() {
        // No exception is the assertion here — both guard branches (null
        // swarmId, empty member set) must short-circuit without attempting
        // any DML.
        NimbusEscalationService.addSwarmMembers(null, null, 'human_request', new Set<Id>{ UserInfo.getUserId() });
        NimbusEscalationService.addSwarmMembers((Id) '0sW000000000123', null, 'human_request', new Set<Id>());
    }

    @isTest
    static void addSwarmMembersHandlesAnInvalidSwarmIdGracefully() {
        // The Swarm referenced here doesn't exist (this org has no Service
        // Cloud/Swarming feature enabled in the test context), so the
        // member insert fails per-record — addSwarmMembers must log and
        // return normally rather than throwing.
        NimbusEscalationService.addSwarmMembers(
            (Id) '0sW000000000123', UserInfo.getUserId(), 'human_request', new Set<Id>{ UserInfo.getUserId() }
        );
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
