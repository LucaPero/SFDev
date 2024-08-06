@RestResource(urlMapping='/lost/*')
global with sharing class AssetService {
    @HttpPost
    global static String reportLostDevice(String assetIdentifier) {
        if(!String.isBlank(assetIdentifier)){
            List<SObject> recordsToInsert = new List<SObject>();
            List<Asset> assetList = [SELECT Id,Status,(SELECT Id from Insurances__r WHERE Active__c = true AND Coverage__c = 'Comprehensive') from Asset WHERE Asset_Identifier__c =:assetIdentifier LIMIT 1];
            if(!assetList.isEmpty()){
                if(!assetList[0].Insurances__r.isEmpty()){
                    Id assetId = assetList[0].Id;
                    List<Claim__c> lossClaims = [SELECT Name from Claim__c WHERE Type__c = 'Loss' AND Asset__c =:assetId LIMIT 1];
                    if(!lossClaims.isEmpty()){
                        return lossClaims[0].Name + ' already filed.';
                    }else{
                        assetList[0].Status = 'Lost';
                        update assetList;
                        Claim__c claim = new Claim__c(Asset__c = assetList[0].Id, Insurance__c = assetList[0].Insurances__r[0].Id, Type__c = 'Loss');
                        insert claim;
                        ID claimId = claim.Id;
                        String claimNumber = [SELECT Name from Claim__c WHERE Id =: claimId].Name;
                        return claimNumber;
                    }
                }else{
                    assetList[0].Status = 'Lost';
                    update assetList;
                    return 'No coverage. Asset status adjusted to Lost.';
                }
            }else{
                return 'No device found.';
            }
        }else{
            return 'No device found.';
        }
    }
}