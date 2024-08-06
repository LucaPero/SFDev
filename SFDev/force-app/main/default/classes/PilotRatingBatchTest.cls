@isTest
public class PilotRatingBatchTest {
    @isTest static void testFailure(){
        insert new Mission__c(Subject__c = 'Test', Status__c = 'Complete');
    
       try {
            Test.startTest();
            Database.executeBatch(new PilotRatingBatch());
            Test.stopTest();
            Test.getEventBus().deliver();
            // Batch Apex job executes here
        } catch(Exception e) {
            // Catch any exceptions thrown in the batch job
        }
        
        // The batch job fires BatchApexErrorEvent if it fails, so deliver the event.
        Test.getEventBus().deliver();
            
        System.assertEquals(1, [SELECT Id FROM Error_Log__c].size());
    }
    
}