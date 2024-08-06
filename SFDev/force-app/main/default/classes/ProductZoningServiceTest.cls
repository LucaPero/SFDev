@isTest
public class ProductZoningServiceTest {
	 @TestSetup
    static void setupTestData() {
        // Set up test data for Product2 (assuming you have a Product record with Family field)
        Product2 product = new Product2(Name='Test Product', ProductCode='XYZ', Family='Fixed-Wing');
        Product2 product2 = new Product2(Name='Test Product 2', ProductCode='ABC', Family='MALE');

        insert product;
        insert product2;

        // Set up test data for Product_Geo_Mapping__mdt
        // Query existing metadata records based on the specified criteria
        List<Product_Geo_Mapping__mdt> mappings = [SELECT Product_Family__c, Permissible_Fly_Zone__c
                                                   FROM Product_Geo_Mapping__mdt
                                                   WHERE Country_Code__c = 'US'];

        // Optionally insert mock data if needed, but typically you'll query existing records
    }

    @isTest
    static void testGetProductZoning_Success() {
        // Mock HTTP request
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/ProductZoning';
        request.addHeader('CountryCode', 'US');
        request.addParameter('ProductCode', 'XYZ');

        // Call the REST service method
        Test.startTest();
        RestContext.request = request;
        String result = ProductZoningService.getProductZoning();
        Test.stopTest();

        // Verify the result
        System.assertEquals('Regulated zones only', result);
    }

    @isTest
    static void testGetProductZoning_ProductCodeMissing() {
        // Mock HTTP request without ProductCode parameter
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/ProductZoning';
        request.addHeader('CountryCode', 'US');

        // Call the REST service method
        Test.startTest();
        RestContext.request = request;
        String result = ProductZoningService.getProductZoning();
        Test.stopTest();

        // Verify the result
        System.assertEquals('ProductCode is missing or doesn\'t exist', result);
    }

    @isTest
    static void testGetProductZoning_NoMappingFound() {
        // Mock HTTP request with existing ProductCode but no mapping found
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/ProductZoning';
        request.addHeader('CountryCode', 'DE');
        request.addParameter('ProductCode', 'ABC'); // Assuming 'ABC' does not have a mapping

        // Call the REST service method
        Test.startTest();
        RestContext.request = request;
        String result = ProductZoningService.getProductZoning();
        Test.stopTest();

        // Verify the result
        System.assertEquals('Confirm with the local authorities', result);
    }
}