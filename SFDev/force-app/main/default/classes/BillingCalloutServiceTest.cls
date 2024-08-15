@isTest
public class BillingCalloutServiceTest {
 @isTest static void testCallout() {
        // Set up test data
        Accessibility_Project__c project = new Accessibility_Project__c();
        project.Amount__c = 100.00;
        insert project;
        Test.setMock(WebServiceMock.class, new BillingCalloutServiceMock());

        Test.startTest();
        // This causes a fake response to be generated
        AccessibilityProjectBilling.callBillingService(project.Id, project.Amount__c);

        Test.stopTest();
        
        // Verify the project status
        project = [SELECT Status__c FROM Accessibility_Project__c WHERE Id = :project.Id];
        System.assertEquals('Complete', project.Status__c, 'Project status should be Complete');
    }
}