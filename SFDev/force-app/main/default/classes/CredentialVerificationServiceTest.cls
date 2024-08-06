@isTest
private class CredentialVerificationServiceTest {

    @isTest
    static void testVerifyCredential_ValidCredential() {
        // Create test data
        Contact testContact = new Contact(
            LastName = 'Smith'
        );
        insert testContact;
        
        Certification__c cert = new Certification__c(Name = 'Test');
        insert cert;

        Contact_Certification__c testCertification = new Contact_Certification__c(
            Contact__c = testContact.Id,
            isActive__c = true,
            Certification__c = cert.Id,
            Issue_Date__c = Date.today()
        );
        insert testCertification;
        String certName = [SELECT Name from Contact_Certification__c WHERE Id =:testCertification.Id]?.Name;
		
        // Test the web service method
        Test.startTest();
        
        String result = CredentialVerificationService.verifyCredential('Smith', certName);
        Test.stopTest();

        // Assert the result
        System.assertEquals('Valid', result, 'Expected credential status did not match');
    }

    @isTest
    static void testVerifyCredential_InactiveCredential() {
        // Create test data
        Contact testContact = new Contact(
            LastName = 'Doe'
        );
        insert testContact;
        
        Certification__c cert = new Certification__c(Name = 'Test');
        insert cert;

        Contact_Certification__c testCertification = new Contact_Certification__c(
            Contact__c = testContact.Id,
            isActive__c = false,
            Certification__c = cert.Id,
            Issue_Date__c = Date.today()
        );
        insert testCertification;

        String certName = [SELECT Name from Contact_Certification__c WHERE Id =:testCertification.Id]?.Name;

        // Test the web service method
        Test.startTest();
        String result = CredentialVerificationService.verifyCredential('Doe', certName);
        Test.stopTest();

        // Assert the result
        System.assertEquals('Needs Renewal', result, 'Expected credential status did not match');
    }

    @isTest
    static void testVerifyCredential_NoContactCertificationFound() {
        // Test the web service method without creating Contact_Certification__c record

        // Test the web service method
        Test.startTest();
        String result = CredentialVerificationService.verifyCredential('UnknownLastName', 'UnknownCertification');
        Test.stopTest();

        // Assert the result
        System.assertEquals('No record found', result, 'Expected credential status did not match');
    }

    @isTest
    static void testVerifyCredential_BlankInputs() {
        // Test the web service method with blank inputs

        // Test the web service method
        Test.startTest();
        String result = CredentialVerificationService.verifyCredential('', '');
        Test.stopTest();

        // Assert the result
        System.assertEquals('No record found', result, 'Expected credential status did not match');
    }
}