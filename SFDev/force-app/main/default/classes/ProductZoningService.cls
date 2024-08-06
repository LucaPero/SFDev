@RestResource(urlMapping='/ProductZoning/*')
global with sharing class ProductZoningService {
    @HttpGet
    global static String getProductZoning() {
        // Get the CountryCode from the request headers
        String countryCode = RestContext.request.headers.get('CountryCode');
        
        // Default CountryCode to 'US' if not found in headers
        if (String.isBlank(countryCode)) {
            countryCode = 'US';
        }
        
        // Retrieve ProductCode from the query parameters
        String productCode = RestContext.request.params.get('ProductCode');
        
        // Call a method to determine permissible fly zones based on countryCode and productCode
        String permissibleZones = getPermissibleZones(productCode, countryCode);
        
        // Return the result
        return permissibleZones;
    }
    
    // Method to query Product Geo Mapping custom metadata and determine permissible zones
    private static String getPermissibleZones(String productCode, String countryCode) {
        List<Product2> productList = [SELECT Family from Product2 WHERE ProductCode =:productCode];
        	
        if(!productList.isEmpty()){
            String family = productList[0]?.Family;
            // Query Product Geo Mapping custom metadata
        	List<Product_Geo_Mapping__mdt> mappings = [SELECT Product_Family__c, Permissible_Fly_Zone__c
                                                   FROM Product_Geo_Mapping__mdt
                                                   WHERE Country_Code__c = :countryCode
                                                   AND Product_Family__c =:family]; 
            system.debug(mappings);
            // Find the product family based on productCode
        	if(!mappings.isEmpty()){
                return mappings[0].Permissible_Fly_Zone__c + ' zones only';
            }else{
                return 'Confirm with the local authorities';
            }
        }else{
            return 'ProductCode is missing or doesn\'t exist';
        }
    }
}