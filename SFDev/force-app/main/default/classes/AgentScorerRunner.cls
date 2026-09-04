/**
 * Retroactively runs Agentforce scorers over agent sessions that have already
 * completed.
 *
 * Wraps the standard `triggerAgentBulkScoring` invocable action. A scorer only
 * evaluates traffic that arrives after the scorer is active, so sessions that
 * ran before a scorer was created never get scored. This class closes that gap.
 *
 * The underlying action is ASYNCHRONOUS and returns no polling handle. A
 * successful invoke means only that the job was accepted -- scores surface
 * later in the `ssot__AiAgentTagAssociation__dlm` Data Cloud DMO.
 *
 * Platform constraints enforced here:
 *   - All input IDs and scorers must belong to the SAME agent.
 *   - Scorers must be `status: Available` with `agentAssociation.isActive: true`.
 *   - Max 500 input IDs and 10 scorers per invocation (larger id lists are
 *     chunked automatically).
 */
public with sharing class AgentScorerRunner {

    public class ScorerRunException extends Exception {}

    public static final String SCOPE_SESSION = 'Session';
    public static final String SCOPE_INTENT = 'Intent';

    public static final Integer MAX_INPUT_IDS = 500;
    public static final Integer MAX_SCORERS = 10;
    public static final Integer MIN_DAYS_BACK = 1;
    public static final Integer MAX_DAYS_BACK = 180;
    public static final Integer DEFAULT_DAYS_BACK = 90;

    private static final String ACTION_NAME = 'triggerAgentBulkScoring';

    /** Outcome of a single `triggerAgentBulkScoring` invocation. */
    public class RunResult {
        public Boolean isSuccess { get; private set; }
        public List<String> inputIds { get; private set; }
        public List<String> errors { get; private set; }

        public RunResult(Boolean isSuccess, List<String> inputIds, List<String> errors) {
            this.isSuccess = isSuccess;
            this.inputIds = inputIds == null ? new List<String>() : inputIds;
            this.errors = errors == null ? new List<String>() : errors;
        }
    }

    /**
     * Seam over the standard action so tests can exercise validation and
     * chunking without invoking the real (callout-backed) action.
     */
    public interface Executor {
        RunResult run(String inputScope, List<String> scorerApiNames, List<String> inputIds, Integer daysBack);
    }

    @TestVisible
    private static Executor executor = new StandardActionExecutor();

    /** Calls the real platform action. */
    private class StandardActionExecutor implements Executor {
        public RunResult run(String inputScope, List<String> scorerApiNames, List<String> inputIds, Integer daysBack) {
            Invocable.Action action = Invocable.Action.createStandardAction(ACTION_NAME);
            action.setInvocationParameter('inputScope', inputScope);
            action.setInvocationParameter('scorerApiNames', scorerApiNames);
            action.setInvocationParameter('inputIds', inputIds);
            action.setInvocationParameter('daysBack', daysBack);

            List<String> errors = new List<String>();
            Boolean success = false;

            for (Invocable.Action.Result result : action.invoke()) {
                success = result.isSuccess();
                if (!success && result.getErrors() != null) {
                    for (Invocable.Action.Error err : result.getErrors()) {
                        errors.add(err.getMessage());
                    }
                }
            }
            return new RunResult(success, inputIds, errors);
        }
    }

    /**
     * Runs the given scorers over the given session IDs using the default
     * 90-day lookback.
     */
    public static List<RunResult> runForSessions(List<String> sessionIds, List<String> scorerApiNames) {
        return run(SCOPE_SESSION, sessionIds, scorerApiNames, DEFAULT_DAYS_BACK);
    }

    /**
     * Runs the given scorers over the given entity IDs.
     *
     * @param inputScope      `Session` or `Intent`.
     * @param inputIds        Session/intent IDs to score. Chunked at 500.
     * @param scorerApiNames  Scorer API names, max 10, all on the same agent.
     * @param daysBack        Lookback window for entity discovery, 1-180.
     * @return                One RunResult per submitted chunk.
     */
    public static List<RunResult> run(
        String inputScope,
        List<String> inputIds,
        List<String> scorerApiNames,
        Integer daysBack
    ) {
        String scope = String.isBlank(inputScope) ? SCOPE_SESSION : inputScope.trim();
        Integer lookback = daysBack == null ? DEFAULT_DAYS_BACK : daysBack;

        validate(scope, inputIds, scorerApiNames, lookback);

        List<RunResult> results = new List<RunResult>();
        for (List<String> chunk : chunk(inputIds, MAX_INPUT_IDS)) {
            results.add(executor.run(scope, scorerApiNames, chunk, lookback));
        }
        return results;
    }

    /** Rejects input the platform action would reject, with a clearer message. */
    @TestVisible
    private static void validate(
        String scope,
        List<String> inputIds,
        List<String> scorerApiNames,
        Integer daysBack
    ) {
        if (scope != SCOPE_SESSION && scope != SCOPE_INTENT) {
            throw new ScorerRunException(
                'inputScope must be "' + SCOPE_SESSION + '" or "' + SCOPE_INTENT + '", got: ' + scope
            );
        }
        if (inputIds == null || inputIds.isEmpty()) {
            throw new ScorerRunException('inputIds is required and cannot be empty.');
        }
        if (scorerApiNames == null || scorerApiNames.isEmpty()) {
            throw new ScorerRunException('scorerApiNames is required and cannot be empty.');
        }
        if (scorerApiNames.size() > MAX_SCORERS) {
            throw new ScorerRunException(
                'A maximum of ' + MAX_SCORERS + ' scorers may run per invocation, got: ' + scorerApiNames.size()
            );
        }
        if (daysBack < MIN_DAYS_BACK || daysBack > MAX_DAYS_BACK) {
            throw new ScorerRunException(
                'daysBack must be between ' + MIN_DAYS_BACK + ' and ' + MAX_DAYS_BACK + ', got: ' + daysBack
            );
        }
    }

    /** Splits a list into sublists of at most `size` entries. */
    @TestVisible
    private static List<List<String>> chunk(List<String> values, Integer size) {
        List<List<String>> chunks = new List<List<String>>();
        List<String> current = new List<String>();

        for (String value : values) {
            current.add(value);
            if (current.size() == size) {
                chunks.add(current);
                current = new List<String>();
            }
        }
        if (!current.isEmpty()) {
            chunks.add(current);
        }
        return chunks;
    }

    // ---------------------------------------------------------------------
    // Async entry point
    // ---------------------------------------------------------------------

    /**
     * Queueable wrapper. The platform action performs a callout, so enqueue
     * this from any context that has already issued DML.
     */
    public class ScorerRunJob implements Queueable, Database.AllowsCallouts {
        private final String inputScope;
        private final List<String> inputIds;
        private final List<String> scorerApiNames;
        private final Integer daysBack;

        public ScorerRunJob(
            String inputScope,
            List<String> inputIds,
            List<String> scorerApiNames,
            Integer daysBack
        ) {
            this.inputScope = inputScope;
            this.inputIds = inputIds;
            this.scorerApiNames = scorerApiNames;
            this.daysBack = daysBack;
        }

        public void execute(QueueableContext context) {
            AgentScorerRunner.run(inputScope, inputIds, scorerApiNames, daysBack);
        }
    }

    /** Enqueues a scoring run and returns the job ID. */
    public static Id runAsync(
        String inputScope,
        List<String> inputIds,
        List<String> scorerApiNames,
        Integer daysBack
    ) {
        return System.enqueueJob(new ScorerRunJob(inputScope, inputIds, scorerApiNames, daysBack));
    }

    // ---------------------------------------------------------------------
    // Flow entry point
    // ---------------------------------------------------------------------

    public class FlowRequest {
        @InvocableVariable(label='Input IDs' description='Session or intent IDs to score.' required=true)
        public List<String> inputIds;

        @InvocableVariable(label='Scorer API Names' description='Scorer API names, max 10, all on the same agent.' required=true)
        public List<String> scorerApiNames;

        @InvocableVariable(label='Input Scope' description='Session or Intent. Defaults to Session.')
        public String inputScope;

        @InvocableVariable(label='Days Back' description='Lookback window, 1-180. Defaults to 90.')
        public Integer daysBack;
    }

    public class FlowResponse {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Batches Submitted')
        public Integer batchesSubmitted;

        @InvocableVariable(label='Error Messages')
        public String errorMessages;
    }

    @InvocableMethod(
        label='Run Agentforce Scorers'
        description='Retroactively runs Agentforce scorers over sessions that already completed.'
        category='Agentforce Scorers'
    )
    public static List<FlowResponse> runFromFlow(List<FlowRequest> requests) {
        List<FlowResponse> responses = new List<FlowResponse>();

        for (FlowRequest request : requests) {
            FlowResponse response = new FlowResponse();
            List<String> errors = new List<String>();
            Boolean allSucceeded = true;
            Integer batches = 0;

            try {
                List<RunResult> results = run(
                    request.inputScope,
                    request.inputIds,
                    request.scorerApiNames,
                    request.daysBack
                );
                batches = results.size();
                for (RunResult result : results) {
                    if (!result.isSuccess) {
                        allSucceeded = false;
                        errors.addAll(result.errors);
                    }
                }
            } catch (Exception e) {
                allSucceeded = false;
                errors.add(e.getMessage());
            }

            response.isSuccess = allSucceeded;
            response.batchesSubmitted = batches;
            response.errorMessages = String.join(errors, '; ');
            responses.add(response);
        }
        return responses;
    }
}