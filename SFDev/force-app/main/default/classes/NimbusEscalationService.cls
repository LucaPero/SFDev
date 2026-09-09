/**
 * Ask Nimbus's one write action (FR6.6). Agent Script calls this from the
 * Escalation subagent whenever a deterministic trigger fires (Appendix B).
 * It creates or updates exactly one Case per conversation session, keyed on
 * the Nimbus_Session_Id__c external ID, so a retried or duplicate trigger
 * within the same session never opens a second Case (FR6.5). Every FR8.1
 * hand-off field is a required @InvocableVariable, so the input contract
 * itself rejects a missing field rather than relying on the model to
 * remember to include one (FR8.2).
 */
public with sharing class NimbusEscalationService {

    private static final Set<String> LEGAL_TRUST_REASON_CODES = new Set<String>{
        'security_keyword', 'gdpr_request'
    };

    private static final Set<String> VALID_REASON_CODES = new Set<String>{
        'human_request', 'security_keyword', 'gdpr_request', 'transactional_intent',
        'account_specific', 'unresolved_after_3_turns', 'no_confident_answer', 'service_degraded'
    };

    private static final Set<String> VALID_SENTIMENT_TRENDS = new Set<String>{
        'improving', 'flat', 'declining'
    };

    // Maps the queueHint a domain subagent passes to the Queue's DeveloperName.
    // Reason codes in LEGAL_TRUST_REASON_CODES always override this (FR8.5).
    private static final Map<String, String> QUEUE_HINT_TO_DEVELOPER_NAME = new Map<String, String>{
        'Billing' => 'Nimbus_Billing',
        'Technical' => 'Nimbus_Technical',
        'General' => 'Nimbus_General',
        'LegalTrust' => 'Nimbus_LegalTrust'
    };

    private static final String DEFAULT_QUEUE_DEVELOPER_NAME = 'Nimbus_General';
    private static final String LEGAL_TRUST_QUEUE_DEVELOPER_NAME = 'Nimbus_LegalTrust';
    private static final String CASE_HOLDING_QUEUE_DEVELOPER_NAME = 'Nimbus_Case_Records';

    @InvocableMethod(
        label='Escalate To Human'
        description='Creates or updates the one Case for this Ask Nimbus conversation session as a background record, and records which human queue the reason code resolves to so the live-chat hand-off can route there.'
    )
    public static List<Result> escalateToHuman(List<Request> requests) {
        Map<String, Id> queueIdByDeveloperName = queueIdsByDeveloperName();

        List<Result> orderedResults = new List<Result>();
        List<Case> validCases = new List<Case>();
        List<Integer> validCaseRequestIndex = new List<Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result r = new Result();
            String validationError = validate(req);
            if (validationError != null) {
                r.isSuccess = false;
                r.errorMessage = validationError;
                orderedResults.add(r);
                continue;
            }

            Case c = new Case();
            c.Nimbus_Session_Id__c = req.sessionId;
            c.Escalation_Reason_Code__c = req.reasonCode;
            c.Intent_Summary__c = req.intentSummary;
            c.Description = req.transcript;
            c.Sentiment_Trend__c = req.sentimentTrend;
            c.Knowledge_Articles_Served__c = req.articlesServed;
            c.Subject = 'Ask Nimbus escalation: ' + req.reasonCode;
            c.Origin = 'Ask Nimbus';

            // The Case is a background record only — it's owned by the non-routed
            // holding queue so it never triggers Omni-Channel's automatic push
            // (that trigger fires on ANY object whose OwnerId is set to a queue
            // that has a QueueRoutingConfig, and that config is per-queue, not
            // per-object-type, so it can't be scoped to "MessagingSession only").
            // Resolved_Queue_Name__c instead records which of the 4 real,
            // routable queues the live-chat outbound flow should use.
            String resolvedQueueDeveloperName = resolveQueueDeveloperName(req.reasonCode, req.queueHint);
            c.Resolved_Queue_Name__c = resolvedQueueDeveloperName;
            Id holdingQueueId = queueIdByDeveloperName.get(CASE_HOLDING_QUEUE_DEVELOPER_NAME);
            if (holdingQueueId != null) {
                c.OwnerId = holdingQueueId;
            }

            validCases.add(c);
            validCaseRequestIndex.add(i);
            orderedResults.add(null); // placeholder, filled in after DML below
        }

        if (!validCases.isEmpty()) {
            Database.UpsertResult[] upsertResults;
            try {
                upsertResults = Database.upsert(
                    validCases, Case.Nimbus_Session_Id__c, false, AccessLevel.USER_MODE
                );
            } catch (Exception e) {
                // Field-level or object-level access failure applies to the whole batch.
                for (Integer j = 0; j < validCases.size(); j++) {
                    Result r = new Result();
                    r.isSuccess = false;
                    r.errorMessage = e.getMessage();
                    orderedResults.set(validCaseRequestIndex[j], r);
                }
                upsertResults = null;
            }

            if (upsertResults != null) {
                List<MessagingSession> sessionsToLink = new List<MessagingSession>();
                List<Case> newlyCreatedCases = new List<Case>();
                List<Id> newlyCreatedCaseIds = new List<Id>();

                for (Integer j = 0; j < upsertResults.size(); j++) {
                    Result r = new Result();
                    Database.UpsertResult ur = upsertResults[j];
                    if (ur.isSuccess()) {
                        r.isSuccess = true;
                        r.caseId = ur.getId();
                        // No manual Omni-Channel push here: the platform automatically
                        // creates a PendingServiceRouting the moment a Case's OwnerId is
                        // set to a queue that has a QueueRoutingConfig attached (verified
                        // against this org's ServiceChannel/QueueRoutingConfig wiring).
                        // Inserting one here as well would fail as a duplicate on every
                        // real escalation.

                        // Tie the live MessagingSession to the Case via the standard
                        // MessagingSession.CaseId lookup, so the two are visibly related
                        // in the Console/record UI instead of only cross-referenced via
                        // Nimbus_Session_Id__c. sessionId is the MessagingSession's own Id
                        // (session_id is linked from @MessagingSession.Id) whenever this
                        // escalation was triggered from a real messaging conversation.
                        String sessionIdValue = validCases[j].Nimbus_Session_Id__c;
                        if (sessionIdValue != null && ((String) sessionIdValue).startsWith('0Mw')) {
                            MessagingSession session = new MessagingSession(
                                Id = (Id) sessionIdValue,
                                CaseId = ur.getId()
                            );
                            sessionsToLink.add(session);
                        }

                        // Only start a swarm the first time this Case is created — a
                        // retried/duplicate trigger in the same session updates the
                        // same Case (isCreated() == false) and must not spin up a
                        // second Slack conversation for it.
                        if (ur.isCreated()) {
                            newlyCreatedCases.add(validCases[j]);
                            newlyCreatedCaseIds.add(ur.getId());
                        }
                    } else {
                        r.isSuccess = false;
                        r.errorMessage = ur.getErrors().isEmpty()
                            ? 'Unknown error creating escalation Case.'
                            : ur.getErrors()[0].getMessage();
                    }
                    orderedResults.set(validCaseRequestIndex[j], r);
                }

                if (!sessionsToLink.isEmpty()) {
                    // Best-effort: a failure here does not affect the Case, which is
                    // already the source of truth — it only means the Console won't
                    // show the Case as related to the conversation from this side.
                    Database.update(sessionsToLink, false, AccessLevel.USER_MODE);
                }

                // Best-effort: pull the routed queue's members into a live Slack
                // swarm on the new Case, so a specialist can work it collaboratively
                // in Slack instead of only picking it up cold from the queue. This
                // org already has service-cloud-swarming enabled with Slack as the
                // collaboration tool. Never fails the escalation itself — Swarming
                // is a bonus channel, not a dependency.
                if (!newlyCreatedCases.isEmpty()) {
                    try {
                        startSwarmsForNewCases(newlyCreatedCases, newlyCreatedCaseIds, queueIdByDeveloperName);
                    } catch (Exception e) {
                        System.debug(LoggingLevel.WARN, 'Ask Nimbus swarm creation failed: ' + e.getMessage());
                    }
                }
            }
        }

        return orderedResults;
    }

    private static String validate(Request req) {
        if (String.isBlank(req.sessionId)) {
            return 'sessionId is required.';
        }
        if (String.isBlank(req.reasonCode) || !VALID_REASON_CODES.contains(req.reasonCode)) {
            return 'reasonCode must be one of: ' + String.join(new List<String>(VALID_REASON_CODES), ', ');
        }
        if (String.isBlank(req.intentSummary)) {
            return 'intentSummary is required.';
        }
        if (String.isBlank(req.transcript)) {
            return 'transcript is required.';
        }
        if (String.isBlank(req.sentimentTrend) || !VALID_SENTIMENT_TRENDS.contains(req.sentimentTrend)) {
            return 'sentimentTrend must be one of: ' + String.join(new List<String>(VALID_SENTIMENT_TRENDS), ', ');
        }
        if (req.articlesServed == null) {
            return 'articlesServed is required (pass an empty string if no articles were served).';
        }
        return null;
    }

    // slackAppId/slackTeamId are tied to THIS org's connected Slack workspace —
    // replace them if this class is ever deployed against a different org.
    private static final String SLACK_APP_ID = 'A01RDL2NJAH';
    private static final String SLACK_TEAM_ID = 'T0BNDJYK61F';

    // Starts a real, live Slack channel for each newly created escalation
    // Case and adds the resolved queue's members as swarm members, so a
    // specialist lands directly in a live Slack conversation with the case
    // context already there — not just a staged record waiting for someone
    // to click a button.
    //
    // This calls the platform's standard createSwarmSlackChannel action
    // through our own unprotected Autolaunched Flow
    // (Create_Swarm_Slack_Channel_Direct) instead of inserting a Swarm
    // record directly. A plain `insert Swarm` only stages the swarm — it
    // never provisions the actual Slack channel (CollaborationUrl stays
    // null), because that requires calling createSwarmSlackChannel, which
    // Apex's Invocable.Action can't reach directly (Swarming isn't on its
    // supported standard-action allowlist). Salesforce's own "Begin
    // Swarming for Slack" flow calls the same action but requires an
    // interactive session (confirmed: it fails headlessly even for a fully
    // permissioned user with "seamless authentication is not configured"),
    // so we wrap the action in our own flow instead — confirmed working
    // with no interactive session required.
    private static void startSwarmsForNewCases(List<Case> newCases, List<Id> newCaseIds, Map<String, Id> queueIdByDeveloperName) {
        Map<Id, Set<Id>> userIdsByQueueId = buildUserIdsByQueueId(queueIdByDeveloperName);

        for (Integer i = 0; i < newCases.size(); i++) {
            Case c = newCases[i];
            Id caseId = newCaseIds[i];

            // createSwarmSlackChannel does real external Slack API work that
            // Apex's test-transaction rollback can't safely unwind —
            // confirmed live: running it inside a test transaction throws a
            // platform UNKNOWN_EXCEPTION, not a normal assertion failure.
            // Skip it in tests the same way you'd skip an HTTP callout;
            // everything around it (channel naming, member lookup, member
            // creation) is still exercised and covered directly.
            if (Test.isRunningTest()) {
                continue;
            }

            String channelName = buildSwarmChannelName(c.Escalation_Reason_Code__c, caseId);
            Map<String, Object> flowInputs = new Map<String, Object>{
                'recordId' => caseId,
                'swarmName' => 'Ask Nimbus escalation: ' + c.Escalation_Reason_Code__c,
                'swarmDescription' => c.Intent_Summary__c,
                'slackChannelName' => channelName,
                'slackAppId' => SLACK_APP_ID,
                'slackTeamId' => SLACK_TEAM_ID
            };

            Id swarmId;
            try {
                Flow.Interview interview = Flow.Interview.createInterview('Create_Swarm_Slack_Channel_Direct', flowInputs);
                interview.start();
                if (interview.getVariableValue('isSuccess') != true) {
                    System.debug(LoggingLevel.WARN, 'Ask Nimbus swarm creation failed for case ' + caseId
                        + ': ' + interview.getVariableValue('errorMessage'));
                    continue;
                }
                swarmId = (Id) String.valueOf(interview.getVariableValue('swarmId'));
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Ask Nimbus swarm creation threw for case ' + caseId + ': ' + e.getMessage());
                continue;
            }

            Id queueId = queueIdByDeveloperName.get(c.Resolved_Queue_Name__c);
            addSwarmMembers(swarmId, caseId, c.Escalation_Reason_Code__c, queueId != null ? userIdsByQueueId.get(queueId) : null);
        }
    }

    private static Map<Id, Set<Id>> buildUserIdsByQueueId(Map<String, Id> queueIdByDeveloperName) {
        Map<Id, Set<Id>> userIdsByQueueId = new Map<Id, Set<Id>>();
        for (GroupMember gm : [
            SELECT GroupId, UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :queueIdByDeveloperName.values() AND UserOrGroupId != null
        ]) {
            if (!((String) gm.UserOrGroupId).startsWith('005')) {
                continue; // skip nested queues/groups — only add actual users
            }
            if (!userIdsByQueueId.containsKey(gm.GroupId)) {
                userIdsByQueueId.put(gm.GroupId, new Set<Id>());
            }
            userIdsByQueueId.get(gm.GroupId).add(gm.UserOrGroupId);
        }
        return userIdsByQueueId;
    }

    @TestVisible
    private static String buildSwarmChannelName(String reasonCode, Id caseId) {
        return 'nimbus-' + reasonCode.replace('_', '-') + '-' + String.valueOf(caseId).right(6).toLowerCase();
    }

    @TestVisible
    private static void addSwarmMembers(Id swarmId, Id caseId, String reasonCode, Set<Id> memberUserIds) {
        if (swarmId == null || memberUserIds == null || memberUserIds.isEmpty()) {
            return;
        }
        List<SwarmMember> members = new List<SwarmMember>();
        for (Id userId : memberUserIds) {
            SwarmMember m = new SwarmMember();
            m.SwarmId = swarmId;
            m.OwnerId = userId;
            m.RelatedRecordId = caseId;
            m.Name = 'Ask Nimbus escalation: ' + reasonCode;
            members.add(m);
        }
        List<Database.SaveResult> memberResults = Database.insert(members, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < memberResults.size(); j++) {
            if (!memberResults[j].isSuccess()) {
                System.debug(LoggingLevel.WARN, 'Ask Nimbus swarm member creation failed for user '
                    + members[j].OwnerId + ' on swarm ' + swarmId + ': ' + memberResults[j].getErrors());
            }
        }
    }

    private static String resolveQueueDeveloperName(String reasonCode, String queueHint) {
        if (LEGAL_TRUST_REASON_CODES.contains(reasonCode)) {
            return LEGAL_TRUST_QUEUE_DEVELOPER_NAME;
        }
        String developerName = QUEUE_HINT_TO_DEVELOPER_NAME.get(queueHint);
        return developerName != null ? developerName : DEFAULT_QUEUE_DEVELOPER_NAME;
    }

    private static Map<String, Id> queueIdsByDeveloperName() {
        Map<String, Id> result = new Map<String, Id>();
        for (Group g : [
            SELECT Id, DeveloperName
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName IN (
                'Nimbus_Billing', 'Nimbus_Technical', 'Nimbus_General', 'Nimbus_LegalTrust',
                'Nimbus_Case_Records'
            )
        ]) {
            result.put(g.DeveloperName, g.Id);
        }
        return result;
    }

    public class Request {
        @InvocableVariable(label='Session Id' description='The Ask Nimbus conversation session id. Idempotency key.' required=true)
        public String sessionId;

        @InvocableVariable(label='Reason Code' description='Which deterministic trigger fired: human_request, security_keyword, gdpr_request, transactional_intent, account_specific, unresolved_after_3_turns, no_confident_answer, or service_degraded.' required=true)
        public String reasonCode;

        @InvocableVariable(label='Intent Summary' description='Short summary of what the user was trying to accomplish.' required=true)
        public String intentSummary;

        @InvocableVariable(label='Transcript' description='The full conversation transcript so far.' required=true)
        public String transcript;

        @InvocableVariable(label='Sentiment Trend' description='One of: improving, flat, declining.' required=true)
        public String sentimentTrend;

        @InvocableVariable(label='Articles Served' description='Source-record IDs of every Knowledge article already served this session, one per line. Pass an empty string if none were served yet.' required=true)
        public String articlesServed;

        @InvocableVariable(label='Queue Hint' description='Which domain queue this subagent maps to: Billing, Technical, or General. Ignored when the reason code is security_keyword or gdpr_request, which always route to the Legal/Trust queue.' required=false)
        public String queueHint;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the Case was created or updated successfully.')
        public Boolean isSuccess;

        @InvocableVariable(label='Case Id' description='Id of the created or updated escalation Case.')
        public Id caseId;

        @InvocableVariable(label='Error Message' description='Error message if the escalation failed.')
        public String errorMessage;
    }
}
