@isTest
public class AssetServiceTest {

    // Common test data setup using @testSetup
    @testSetup
    static void setupTestData() {
        Account newAcc = new Account(Name='Test');
        insert newAcc;
        
        Asset testAssetWithCoverage = new Asset(
            Asset_Identifier__c = 'TEST123',
            Status = 'Active',
            Name = 'Test 1',
            AccountId = newAcc.Id
        );
        insert testAssetWithCoverage;

        Insurance__c testInsurance = new Insurance__c(
            Asset__c = testAssetWithCoverage.Id,
            Active__c = true,
            Coverage__c = 'Comprehensive'
        );
        insert testInsurance;

        Asset testAssetWithoutCoverage = new Asset(
            Asset_Identifier__c = 'TEST456',
            Status = 'Active',
            Name = 'Test 2',
            AccountId = newAcc.Id
        );
        insert testAssetWithoutCoverage;

        Asset testAssetAlreadyFiled = new Asset(
            Asset_Identifier__c = 'TEST789',
            Status = 'Active',
            Name = 'Test 3',
            AccountId = newAcc.Id
        );
        insert testAssetAlreadyFiled;

        Insurance__c testInsuranceAlreadyFiled = new Insurance__c(
            Asset__c = testAssetAlreadyFiled.Id,
            Active__c = true,
            Coverage__c = 'Comprehensive'
        );
        insert testInsuranceAlreadyFiled;

        Claim__c testClaimAlreadyFiled = new Claim__c(
            Asset__c = testAssetAlreadyFiled.Id,
            Insurance__c = testInsuranceAlreadyFiled.Id,
            Type__c = 'Loss'
        );
        insert testClaimAlreadyFiled;
    }

    @isTest
    static void testReportLostDevice_withCoverage() {
        // Test the REST service method
        Test.startTest();
        String response = AssetService.reportLostDevice('TEST123');
        List<Claim__c> lossClaims = [SELECT Name from Claim__c WHERE Type__c = 'Loss' AND Asset__r.Asset_Identifier__c = 'TEST123' LIMIT 1];
        Test.stopTest();

        // Assert the results
        System.assertEquals(lossClaims[0].Name, response);
    }

    @isTest
    static void testReportLostDevice_noCoverage() {
        // Test the REST service method
        Test.startTest();
        String response = AssetService.reportLostDevice('TEST456');
        Test.stopTest();

        // Assert the results
        System.assertEquals('No coverage. Asset status adjusted to Lost.', response);
    }

    @isTest
    static void testReportLostDevice_alreadyFiled() {
        // Test the REST service method
        Test.startTest();
        String response = AssetService.reportLostDevice('TEST789');
        List<Claim__c> lossClaims = [SELECT Name from Claim__c WHERE Type__c = 'Loss' AND Asset__r.Asset_Identifier__c = 'TEST789' LIMIT 1];
        Test.stopTest();

        // Assert the results
        System.assertEquals(lossClaims[0].Name +' already filed.', response);
    }

    @isTest
    static void testReportLostDevice_noDeviceFound() {
        // Test the REST service method
        Test.startTest();
        String response = AssetService.reportLostDevice('NONEXISTENT');
        Test.stopTest();

        // Assert the results
        System.assertEquals('No device found.', response);
    }
}