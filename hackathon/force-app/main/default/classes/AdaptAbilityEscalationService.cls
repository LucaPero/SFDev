/**
 * AdaptAbility's one write action. Agent Script calls this from the
 * Escalation subagent whenever a deterministic trigger fires. It creates or
 * updates exactly one Case per conversation session, keyed on the
 * AdaptAbility_Session_Id__c external ID, so a retried or duplicate trigger
 * within the same session never opens a second Case. Every hand-off field is
 * a required @InvocableVariable, so the input contract itself rejects a
 * missing field rather than relying on the model to remember to include one.
 */
public with sharing class AdaptAbilityEscalationService {

    private static final Set<String> PRIVACY_LEGAL_REASON_CODES = new Set<String>{
        'privacy_concern', 'data_privacy_request'
    };

    private static final Set<String> VALID_REASON_CODES = new Set<String>{
        'human_request', 'privacy_concern', 'data_privacy_request', 'action_required',
        'employee_specific_case_data', 'unresolved_after_3_turns', 'no_confident_answer',
        'service_degraded', 'urgent_deadline_or_safety'
    };

    private static final Set<String> VALID_SENTIMENT_TRENDS = new Set<String>{
        'improving', 'flat', 'declining'
    };

    private static final Map<String, String> QUEUE_HINT_TO_DEVELOPER_NAME = new Map<String, String>{
        'Accommodations' => 'AdaptAbility_Accommodations',
        'CustomerAccess' => 'AdaptAbility_CustomerAccess',
        'General' => 'AdaptAbility_General'
    };

    private static final String DEFAULT_QUEUE_DEVELOPER_NAME = 'AdaptAbility_General';
    private static final String PRIVACY_LEGAL_QUEUE_DEVELOPER_NAME = 'AdaptAbility_PrivacyLegal';
    private static final String CASE_HOLDING_QUEUE_DEVELOPER_NAME = 'AdaptAbility_Case_Records';

    @InvocableMethod(
        label='Escalate To Human'
        description='Creates or updates the one Case for this AdaptAbility conversation session as a background record, and records which human queue the reason code resolves to so the live-chat hand-off can route there.'
    )
    public static List<Result> escalateToHuman(List<Request> requests) {
        Map<String, Id> queueIdByDeveloperName = queueIdsByDeveloperName();

        List<Result> orderedResults = new List<Result>();
        List<Case> validCases = new List<Case>();
        List<Integer> validCaseRequestIndex = new List<Integer>();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result r = new Result();

            // Logged unconditionally, before validation or sanitization, so a
            // debug log always shows exactly what Agent Script actually sent —
            // this is the fastest way to tell whether an "articles missing"
            // report is an Apex bug or an upstream capture gap.
            System.debug(LoggingLevel.INFO,
                'AdaptAbility escalateToHuman received: sessionId=' + req.sessionId
                + ' reasonCode=' + req.reasonCode
                + ' articlesServed=[' + req.articlesServed + ']'
            );

            String validationError = validate(req);
            if (validationError != null) {
                System.debug(LoggingLevel.WARN, 'AdaptAbility escalateToHuman validation failed: ' + validationError);
                r.isSuccess = false;
                r.errorMessage = validationError;
                orderedResults.add(r);
                continue;
            }

            Case c = new Case();
            c.AdaptAbility_Session_Id__c = req.sessionId;
            c.Escalation_Reason_Code__c = req.reasonCode;
            c.Intent_Summary__c = req.intentSummary;
            c.Description = req.transcript;
            c.Sentiment_Trend__c = req.sentimentTrend;
            c.Knowledge_Articles_Served__c = sanitizeArticlesServed(req.articlesServed);
            System.debug(LoggingLevel.INFO,
                'AdaptAbility sanitizeArticlesServed: raw=[' + req.articlesServed
                + '] sanitized=[' + c.Knowledge_Articles_Served__c + ']'
            );
            c.Subject = 'AdaptAbility escalation: ' + req.reasonCode;
            c.Origin = 'AdaptAbility';

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
                    validCases, Case.AdaptAbility_Session_Id__c, false, AccessLevel.USER_MODE
                );
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'AdaptAbility escalateToHuman upsert threw: ' + e.getMessage() + '\n' + e.getStackTraceString());
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
                Set<Id> successfulCaseIds = new Set<Id>();
                for (Database.UpsertResult ur : upsertResults) {
                    if (ur.isSuccess()) {
                        successfulCaseIds.add(ur.getId());
                    }
                }
                Map<Id, String> caseNumberById = new Map<Id, String>();
                if (!successfulCaseIds.isEmpty()) {
                    for (Case c : [SELECT Id, CaseNumber FROM Case WHERE Id IN :successfulCaseIds]) {
                        caseNumberById.put(c.Id, c.CaseNumber);
                    }
                }

                List<MessagingSession> sessionsToLink = new List<MessagingSession>();
                List<EscalationEmailContext> emailContexts = new List<EscalationEmailContext>();

                for (Integer j = 0; j < upsertResults.size(); j++) {
                    Result r = new Result();
                    Database.UpsertResult ur = upsertResults[j];
                    if (ur.isSuccess()) {
                        r.isSuccess = true;
                        r.caseId = ur.getId();
                        r.caseNumber = caseNumberById.get(ur.getId());

                        // No manual Omni-Channel push here — the platform already
                        // creates a PendingServiceRouting when OwnerId is set to a
                        // queue with a QueueRoutingConfig attached.

                        // Ties the live MessagingSession to the Case so they're
                        // visibly related in the Console.
                        String sessionIdValue = validCases[j].AdaptAbility_Session_Id__c;
                        if (sessionIdValue != null && ((String) sessionIdValue).startsWith('0Mw')) {
                            MessagingSession session = new MessagingSession(
                                Id = (Id) sessionIdValue,
                                CaseId = ur.getId()
                            );
                            sessionsToLink.add(session);
                        }

                        EscalationEmailContext ctx = new EscalationEmailContext();
                        ctx.caseId = ur.getId();
                        ctx.resolvedQueueDeveloperName = validCases[j].Resolved_Queue_Name__c;
                        ctx.reasonCode = validCases[j].Escalation_Reason_Code__c;
                        ctx.intentSummary = validCases[j].Intent_Summary__c;
                        ctx.sentimentTrend = validCases[j].Sentiment_Trend__c;
                        ctx.articlesServed = validCases[j].Knowledge_Articles_Served__c;
                        emailContexts.add(ctx);
                    } else {
                        r.isSuccess = false;
                        r.errorMessage = ur.getErrors().isEmpty()
                            ? 'Unknown error creating escalation Case.'
                            : ur.getErrors()[0].getMessage();
                        System.debug(LoggingLevel.ERROR, 'AdaptAbility escalateToHuman Case upsert failed: ' + r.errorMessage);
                    }
                    orderedResults.set(validCaseRequestIndex[j], r);
                }

                if (!sessionsToLink.isEmpty()) {
                    // Best-effort — a failure here doesn't affect the Case itself.
                    Database.update(sessionsToLink, false, AccessLevel.USER_MODE);
                }

                // No Service Cloud license in this org, so Omni-Channel can't push
                // to a live rep — a queue-membership email is the only real-time
                // notification a human gets. Must never fail the escalation itself.
                if (!emailContexts.isEmpty()) {
                    try {
                        sendEscalationEmails(emailContexts, queueIdByDeveloperName, caseNumberById);
                    } catch (Exception e) {
                        System.debug(LoggingLevel.WARN, 'AdaptAbility escalation email notification failed: ' + e.getMessage());
                    }
                }
            }
        }

        return orderedResults;
    }

    // Sends one context-rich email per escalation Case to the resolved queue's
    // members — the specialist already knows the reason, what the person was
    // trying to do, and which articles were already tried, so the person never
    // has to re-explain themselves once a human picks up the Case.
    private static void sendEscalationEmails(List<EscalationEmailContext> contexts, Map<String, Id> queueIdByDeveloperName, Map<Id, String> caseNumberById) {
        Set<Id> queueIds = new Set<Id>();
        for (EscalationEmailContext ctx : contexts) {
            Id queueId = queueIdByDeveloperName.get(ctx.resolvedQueueDeveloperName);
            if (queueId != null) {
                queueIds.add(queueId);
            }
        }
        if (queueIds.isEmpty()) {
            return;
        }

        Map<Id, Set<Id>> userIdsByQueueId = new Map<Id, Set<Id>>();
        Set<Id> allUserIds = new Set<Id>();
        for (GroupMember gm : [
            SELECT GroupId, UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :queueIds AND UserOrGroupId != null
        ]) {
            if (!((String) gm.UserOrGroupId).startsWith('005')) {
                continue; // skip nested queues/groups — only email actual users
            }
            if (!userIdsByQueueId.containsKey(gm.GroupId)) {
                userIdsByQueueId.put(gm.GroupId, new Set<Id>());
            }
            userIdsByQueueId.get(gm.GroupId).add(gm.UserOrGroupId);
            allUserIds.add(gm.UserOrGroupId);
        }
        if (allUserIds.isEmpty()) {
            return;
        }

        Map<Id, String> emailByUserId = new Map<Id, String>();
        for (User u : [SELECT Id, Email FROM User WHERE Id IN :allUserIds AND Email != null]) {
            emailByUserId.put(u.Id, u.Email);
        }

        Set<Id> articleIds = new Set<Id>();
        for (EscalationEmailContext ctx : contexts) {
            for (String line : splitLines(ctx.articlesServed)) {
                if (isKnowledgeArticleId(line)) {
                    articleIds.add((Id) line);
                }
            }
        }
        Map<Id, String> articleTitleById = new Map<Id, String>();
        if (!articleIds.isEmpty()) {
            for (Knowledge__kav ka : [SELECT Id, Title FROM Knowledge__kav WHERE Id IN :articleIds]) {
                articleTitleById.put(ka.Id, ka.Title);
            }
        }

        String orgBaseUrl = Url.getOrgDomainUrl().toExternalForm();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (EscalationEmailContext ctx : contexts) {
            Id queueId = queueIdByDeveloperName.get(ctx.resolvedQueueDeveloperName);
            Set<Id> memberIds = queueId != null ? userIdsByQueueId.get(queueId) : null;
            if (memberIds == null || memberIds.isEmpty()) {
                continue;
            }
            List<String> toAddresses = new List<String>();
            for (Id userId : memberIds) {
                String email = emailByUserId.get(userId);
                if (email != null) {
                    toAddresses.add(email);
                }
            }
            if (toAddresses.isEmpty()) {
                continue;
            }

            // articlesServed isn't guaranteed to be a Salesforce record ID —
            // it may be a plain article title, or the actual knowledgeSummary
            // prose captured from the retrieval action. Resolve an ID to its
            // title when possible; otherwise show the raw value as-is.
            List<String> articleLines = new List<String>();
            for (String line : splitLines(ctx.articlesServed)) {
                if (line.equalsIgnoreCase('none') || isNoAnswerLine(line)) {
                    continue;
                }
                if (isKnowledgeArticleId(line)) {
                    articleLines.add('- ' + (articleTitleById.containsKey((Id) line) ? articleTitleById.get((Id) line) : line));
                } else {
                    articleLines.add('- ' + line);
                }
            }
            String articlesSection = articleLines.isEmpty()
                ? 'None shown yet.'
                : String.join(articleLines, '\n');

            // Attach the actual content shown this session as a file, so the
            // specialist has it in hand rather than just a one-line mention —
            // built straight from articlesServed, no separate Id/lookup needed.
            List<Messaging.EmailFileAttachment> articleAttachments = new List<Messaging.EmailFileAttachment>();
            if (!articleLines.isEmpty()) {
                Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
                attachment.setFileName('Knowledge Content Shown.txt');
                attachment.setBody(Blob.valueOf(stripHtmlTags(articlesSection)));
                articleAttachments.add(attachment);
            }

            String caseNumber = caseNumberById.get(ctx.caseId);
            String recordLink = orgBaseUrl + '/' + ctx.caseId;

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(toAddresses);
            email.setSenderDisplayName('AdaptAbility');
            email.setSubject('AdaptAbility escalation: ' + ctx.reasonCode + ' (Case #' + caseNumber + ')');
            email.setPlainTextBody(
                'A new AdaptAbility escalation needs your attention.\n\n' +
                'Reason: ' + ctx.reasonCode + '\n' +
                'Session sentiment: ' + ctx.sentimentTrend + '\n\n' +
                'What the person was trying to do:\n' + ctx.intentSummary + '\n\n' +
                'Articles already shown (may not have resolved it):\n' + articlesSection
                + (articleAttachments.isEmpty() ? '' : '\n(attached below as text files)') + '\n\n' +
                'Open the case: ' + recordLink + '\n\n' +
                'This case already has the full context above — no need to ask the person to repeat themselves.'
            );
            email.setWhatId(ctx.caseId);
            email.setSaveAsActivity(true);
            if (!articleAttachments.isEmpty()) {
                email.setFileAttachments(articleAttachments);
            }
            emails.add(email);
        }

        if (!emails.isEmpty()) {
            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(emails, false);
            for (Integer i = 0; i < sendResults.size(); i++) {
                Messaging.SendEmailResult sr = sendResults[i];
                if (sr.isSuccess()) {
                    System.debug(LoggingLevel.INFO, 'AdaptAbility escalation email ' + i + ' queued successfully.');
                } else {
                    for (Messaging.SendEmailError err : sr.getErrors()) {
                        System.debug(LoggingLevel.ERROR,
                            'AdaptAbility escalation email ' + i + ' failed: ' + err.getMessage()
                            + ' (status code: ' + err.getStatusCode() + ')'
                        );
                    }
                }
            }
        }
    }

    private static List<String> splitLines(String value) {
        List<String> result = new List<String>();
        if (String.isBlank(value)) {
            return result;
        }
        for (String line : value.split('\n')) {
            String trimmed = line.trim();
            if (String.isNotBlank(trimmed)) {
                result.add(trimmed);
            }
        }
        return result;
    }

    private static Boolean isKnowledgeArticleId(String value) {
        return value != null && value.startsWith('ka0') && (value.length() == 15 || value.length() == 18);
    }

    private static String stripHtmlTags(String value) {
        if (value == null) {
            return '';
        }
        return value.replaceAll('<[^>]+>', '').replaceAll('&nbsp;', ' ').trim();
    }

    // AnswerQuestionsWithKnowledge's own knowledgeSummary output is a
    // "sorry, no answer" apology (not an empty string) when retrieval finds
    // nothing relevant, and Agent Script captures that output unconditionally
    // on every call — so a failed search can end up looking like a served
    // article unless it's filtered out here, both from storage and from the
    // specialist-facing email.
    private static Boolean isNoAnswerLine(String value) {
        if (value == null) {
            return false;
        }
        // Deliberately narrow: require the line to both open with the apology
        // AND contain the "find an answer" phrase, so a genuinely useful
        // summary that merely hedges partway through ("no relevant
        // information specifically about X, but...") is never mistaken for a
        // fully failed search.
        String lower = value.trim().toLowerCase();
        return lower.startsWith('sorry')
            && (lower.contains('find an answer') || lower.contains('find any answer'));
    }

    private static String sanitizeArticlesServed(String raw) {
        List<String> kept = new List<String>();
        for (String line : splitLines(raw)) {
            if (line.equalsIgnoreCase('none') || isNoAnswerLine(line)) {
                continue;
            }
            kept.add(line);
        }
        return kept.isEmpty() ? 'none' : String.join(kept, '\n');
    }

    private class EscalationEmailContext {
        Id caseId;
        String resolvedQueueDeveloperName;
        String reasonCode;
        String intentSummary;
        String sentimentTrend;
        String articlesServed;
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

    private static String resolveQueueDeveloperName(String reasonCode, String queueHint) {
        if (PRIVACY_LEGAL_REASON_CODES.contains(reasonCode)) {
            return PRIVACY_LEGAL_QUEUE_DEVELOPER_NAME;
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
                'AdaptAbility_Accommodations', 'AdaptAbility_CustomerAccess', 'AdaptAbility_General',
                'AdaptAbility_PrivacyLegal', 'AdaptAbility_Case_Records'
            )
        ]) {
            result.put(g.DeveloperName, g.Id);
        }
        return result;
    }

    public class Request {
        @InvocableVariable(label='Session Id' description='The AdaptAbility conversation session id. Idempotency key.' required=true)
        public String sessionId;

        @InvocableVariable(label='Reason Code' description='Which deterministic trigger fired: human_request, privacy_concern, data_privacy_request, action_required, employee_specific_case_data, unresolved_after_3_turns, no_confident_answer, service_degraded, or urgent_deadline_or_safety.' required=true)
        public String reasonCode;

        @InvocableVariable(label='Intent Summary' description='Short summary of what the user was trying to accomplish.' required=true)
        public String intentSummary;

        @InvocableVariable(label='Transcript' description='The full conversation transcript so far.' required=true)
        public String transcript;

        @InvocableVariable(label='Sentiment Trend' description='One of: improving, flat, declining.' required=true)
        public String sentimentTrend;

        @InvocableVariable(label='Articles Served' description='Source-record IDs of every Knowledge article already served this session, one per line. Pass an empty string if none were served yet.' required=true)
        public String articlesServed;

        @InvocableVariable(label='Queue Hint' description='Which track this subagent maps to: Accommodations (employee) or CustomerAccess (customer). Ignored when the reason code is privacy_concern or data_privacy_request, which always route to the Privacy/Legal queue.' required=false)
        public String queueHint;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='Whether the Case was created or updated successfully.')
        public Boolean isSuccess;

        @InvocableVariable(label='Case Id' description='Id of the created or updated escalation Case.')
        public Id caseId;

        @InvocableVariable(label='Case Number' description='Human-readable case number to give back to the requester as a reference/tracking number.')
        public String caseNumber;

        @InvocableVariable(label='Error Message' description='Error message if the escalation failed.')
        public String errorMessage;
    }
}
