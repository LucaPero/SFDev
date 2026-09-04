/**
 * Tests for AgentScorerRunner.
 *
 * The real `triggerAgentBulkScoring` action performs a callout and writes to
 * Data Cloud, so these tests swap in a stub Executor and assert on the
 * validation, chunking, and Flow-adapter logic instead.
 */
@IsTest
private class AgentScorerRunnerTest {

    private static final String SESSION_A = '01a02c23-79b2-72fa-b9b4-a5518af9d0cb';
    private static final String SESSION_B = '4452f22e-49dc-4cb5-bc02-3b7e93170c4d';

    private static final List<String> CUSTOM_SCORERS = new List<String>{
        'Field_Completeness',
        'Friction_Eval_Lead_Insight_Agent',
        'Lead_Insight_Multi_Dimensions_Eval'
    };

    /** Records what it was called with instead of hitting the platform action. */
    private class StubExecutor implements AgentScorerRunner.Executor {
        public Integer callCount = 0;
        public List<List<String>> receivedIdChunks = new List<List<String>>();
        public String receivedScope;
        public List<String> receivedScorers;
        public Integer receivedDaysBack;
        public Boolean succeed = true;

        public AgentScorerRunner.RunResult run(
            String inputScope,
            List<String> scorerApiNames,
            List<String> inputIds,
            Integer daysBack
        ) {
            callCount++;
            receivedScope = inputScope;
            receivedScorers = scorerApiNames;
            receivedDaysBack = daysBack;
            receivedIdChunks.add(inputIds);

            return new AgentScorerRunner.RunResult(
                succeed,
                inputIds,
                succeed ? new List<String>() : new List<String>{ 'stub failure' }
            );
        }
    }

    private static StubExecutor useStub() {
        StubExecutor stub = new StubExecutor();
        AgentScorerRunner.executor = stub;
        return stub;
    }

    private static List<String> makeIds(Integer count) {
        List<String> ids = new List<String>();
        for (Integer i = 0; i < count; i++) {
            ids.add('session-' + i);
        }
        return ids;
    }

    @IsTest
    static void runForSessionsPassesScopeAndDefaultLookback() {
        StubExecutor stub = useStub();

        Test.startTest();
        List<AgentScorerRunner.RunResult> results = AgentScorerRunner.runForSessions(
            new List<String>{ SESSION_A, SESSION_B },
            CUSTOM_SCORERS
        );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Two IDs should submit as a single batch');
        Assert.isTrue(results[0].isSuccess, 'Stub reports success');
        Assert.areEqual(AgentScorerRunner.SCOPE_SESSION, stub.receivedScope, 'Scope should default to Session');
        Assert.areEqual(AgentScorerRunner.DEFAULT_DAYS_BACK, stub.receivedDaysBack, 'Lookback should default to 90');
        Assert.areEqual(CUSTOM_SCORERS, stub.receivedScorers, 'Scorers should pass through unchanged');
        Assert.areEqual(
            new List<String>{ SESSION_A, SESSION_B },
            stub.receivedIdChunks[0],
            'Session IDs should pass through unchanged'
        );
    }

    @IsTest
    static void blankScopeDefaultsToSession() {
        StubExecutor stub = useStub();

        Test.startTest();
        AgentScorerRunner.run(null, new List<String>{ SESSION_A }, CUSTOM_SCORERS, 7);
        Test.stopTest();

        Assert.areEqual(AgentScorerRunner.SCOPE_SESSION, stub.receivedScope, 'Null scope should fall back to Session');
        Assert.areEqual(7, stub.receivedDaysBack, 'Explicit lookback should be honoured');
    }

    @IsTest
    static void idsAboveLimitAreChunked() {
        StubExecutor stub = useStub();
        List<String> ids = makeIds(1150);

        Test.startTest();
        List<AgentScorerRunner.RunResult> results = AgentScorerRunner.run(
            AgentScorerRunner.SCOPE_SESSION,
            ids,
            CUSTOM_SCORERS,
            30
        );
        Test.stopTest();

        Assert.areEqual(3, results.size(), '1150 IDs should split into 3 batches');
        Assert.areEqual(3, stub.callCount, 'Executor should be called once per batch');
        Assert.areEqual(500, stub.receivedIdChunks[0].size(), 'First batch should be full');
        Assert.areEqual(500, stub.receivedIdChunks[1].size(), 'Second batch should be full');
        Assert.areEqual(150, stub.receivedIdChunks[2].size(), 'Final batch holds the remainder');
    }

    @IsTest
    static void exactLimitProducesSingleChunk() {
        StubExecutor stub = useStub();

        Test.startTest();
        AgentScorerRunner.run(AgentScorerRunner.SCOPE_SESSION, makeIds(500), CUSTOM_SCORERS, 30);
        Test.stopTest();

        Assert.areEqual(1, stub.callCount, 'Exactly 500 IDs should not spill into a second batch');
    }

    @IsTest
    static void invalidScopeIsRejected() {
        useStub();

        Test.startTest();
        try {
            AgentScorerRunner.run('Interaction', new List<String>{ SESSION_A }, CUSTOM_SCORERS, 30);
            Assert.fail('Expected ScorerRunException for unsupported scope');
        } catch (AgentScorerRunner.ScorerRunException e) {
            Assert.isTrue(e.getMessage().contains('inputScope'), 'Message should name the offending parameter');
        }
        Test.stopTest();
    }

    @IsTest
    static void emptyInputIdsAreRejected() {
        useStub();

        Test.startTest();
        try {
            AgentScorerRunner.run(AgentScorerRunner.SCOPE_SESSION, new List<String>(), CUSTOM_SCORERS, 30);
            Assert.fail('Expected ScorerRunException for empty inputIds');
        } catch (AgentScorerRunner.ScorerRunException e) {
            Assert.isTrue(e.getMessage().contains('inputIds'), 'Message should name the offending parameter');
        }
        Test.stopTest();
    }

    @IsTest
    static void emptyScorersAreRejected() {
        useStub();

        Test.startTest();
        try {
            AgentScorerRunner.run(
                AgentScorerRunner.SCOPE_SESSION,
                new List<String>{ SESSION_A },
                new List<String>(),
                30
            );
            Assert.fail('Expected ScorerRunException for empty scorerApiNames');
        } catch (AgentScorerRunner.ScorerRunException e) {
            Assert.isTrue(e.getMessage().contains('scorerApiNames'), 'Message should name the offending parameter');
        }
        Test.stopTest();
    }

    @IsTest
    static void tooManyScorersAreRejected() {
        useStub();
        List<String> scorers = new List<String>();
        for (Integer i = 0; i < 11; i++) {
            scorers.add('Scorer_' + i);
        }

        Test.startTest();
        try {
            AgentScorerRunner.run(AgentScorerRunner.SCOPE_SESSION, new List<String>{ SESSION_A }, scorers, 30);
            Assert.fail('Expected ScorerRunException for more than 10 scorers');
        } catch (AgentScorerRunner.ScorerRunException e) {
            Assert.isTrue(e.getMessage().contains('10 scorers'), 'Message should state the scorer ceiling');
        }
        Test.stopTest();
    }

    @IsTest
    static void daysBackOutOfRangeIsRejected() {
        useStub();

        Test.startTest();
        try {
            AgentScorerRunner.run(AgentScorerRunner.SCOPE_SESSION, new List<String>{ SESSION_A }, CUSTOM_SCORERS, 181);
            Assert.fail('Expected ScorerRunException for daysBack above 180');
        } catch (AgentScorerRunner.ScorerRunException e) {
            Assert.isTrue(e.getMessage().contains('daysBack'), 'Message should name the offending parameter');
        }

        try {
            AgentScorerRunner.run(AgentScorerRunner.SCOPE_SESSION, new List<String>{ SESSION_A }, CUSTOM_SCORERS, 0);
            Assert.fail('Expected ScorerRunException for daysBack below 1');
        } catch (AgentScorerRunner.ScorerRunException e) {
            Assert.isTrue(e.getMessage().contains('daysBack'), 'Message should name the offending parameter');
        }
        Test.stopTest();
    }

    @IsTest
    static void flowAdapterReportsSuccess() {
        StubExecutor stub = useStub();

        AgentScorerRunner.FlowRequest request = new AgentScorerRunner.FlowRequest();
        request.inputIds = new List<String>{ SESSION_A, SESSION_B };
        request.scorerApiNames = CUSTOM_SCORERS;
        request.inputScope = AgentScorerRunner.SCOPE_SESSION;
        request.daysBack = 7;

        Test.startTest();
        List<AgentScorerRunner.FlowResponse> responses = AgentScorerRunner.runFromFlow(
            new List<AgentScorerRunner.FlowRequest>{ request }
        );
        Test.stopTest();

        Assert.areEqual(1, responses.size(), 'One response per request');
        Assert.isTrue(responses[0].isSuccess, 'Stub run should report success');
        Assert.areEqual(1, responses[0].batchesSubmitted, 'Two IDs form one batch');
        Assert.areEqual('', responses[0].errorMessages, 'No errors expected on the happy path');
        Assert.areEqual(7, stub.receivedDaysBack, 'Flow lookback should reach the executor');
    }

    @IsTest
    static void flowAdapterSurfacesValidationErrors() {
        useStub();

        AgentScorerRunner.FlowRequest request = new AgentScorerRunner.FlowRequest();
        request.inputIds = new List<String>();
        request.scorerApiNames = CUSTOM_SCORERS;

        Test.startTest();
        List<AgentScorerRunner.FlowResponse> responses = AgentScorerRunner.runFromFlow(
            new List<AgentScorerRunner.FlowRequest>{ request }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].isSuccess, 'Validation failure should not report success');
        Assert.areEqual(0, responses[0].batchesSubmitted, 'Nothing should be submitted');
        Assert.isTrue(
            responses[0].errorMessages.contains('inputIds'),
            'Flow should surface the validation message rather than throw'
        );
    }

    @IsTest
    static void flowAdapterSurfacesExecutorErrors() {
        StubExecutor stub = useStub();
        stub.succeed = false;

        AgentScorerRunner.FlowRequest request = new AgentScorerRunner.FlowRequest();
        request.inputIds = new List<String>{ SESSION_A };
        request.scorerApiNames = CUSTOM_SCORERS;

        Test.startTest();
        List<AgentScorerRunner.FlowResponse> responses = AgentScorerRunner.runFromFlow(
            new List<AgentScorerRunner.FlowRequest>{ request }
        );
        Test.stopTest();

        Assert.isFalse(responses[0].isSuccess, 'Executor failure should propagate');
        Assert.isTrue(responses[0].errorMessages.contains('stub failure'), 'Executor errors should be joined into the response');
    }

    @IsTest
    static void runAsyncEnqueuesJob() {
        useStub();

        Test.startTest();
        Id jobId = AgentScorerRunner.runAsync(
            AgentScorerRunner.SCOPE_SESSION,
            new List<String>{ SESSION_A, SESSION_B },
            CUSTOM_SCORERS,
            7
        );
        Test.stopTest();

        Assert.isNotNull(jobId, 'Queueable should return a job ID');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM AsyncApexJob WHERE Id = :jobId],
            'Job should be recorded'
        );
    }
}