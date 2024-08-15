@isTest
public class RewardsCalloutServiceTest {
    @isTest static void testSubmitUsersForRewardCallout() {
        Test.setMock(HttpCalloutMock.class, new RewardsCalloutServiceMock());

        // Create test data for Wellness Journey
        List<Wellness_Journey__c> journeys = new List<Wellness_Journey__c>();
        User testUser = [SELECT Id, Name, Username, Email FROM User WHERE Id = :UserInfo.getUserId()];
        
        for (Integer i = 0; i < 12; i++) {
            Wellness_Journey__c journey = new Wellness_Journey__c(
                OwnerId = testUser.Id
            );
            journeys.add(journey);
        }
        insert journeys;

        Test.startTest();
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        // Assertions to validate the behavior can be added here
        Integer statusCode = RewardsCalloutService.submitUsersForRewardCallout(JSON.serialize(journeys));
        System.assertEquals(201, statusCode, 'The HTTP status code should be 201');
    }
    @isTest static void testFailure(){
        Test.startTest();
        Database.executeBatch(new WellnessJourneyRewardsBatch());
        Test.stopTest();

        // Assertions to validate the behavior can be added here
        Integer statusCode = RewardsCalloutService.submitUsersForRewardCallout(JSON.serialize(''));
        System.assertEquals(500, statusCode, 'The HTTP status code should be 500');
    }
}