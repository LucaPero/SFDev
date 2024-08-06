global with sharing class CredentialVerificationService {
    webservice static String verifyCredential (String contactLastName, String contactCertificationName) {
        String credentialStatus = 'No record found';
        if(!String.isBlank(contactLastName) && !String.isBlank(contactCertificationName)){
            List<Contact_Certification__c> contactCerts = [SELECT isActive__c from Contact_Certification__c WHERE Contact__r.LastName =:contactLastName AND Name =:contactCertificationName LIMIT 1];
            if(!contactCerts.isEmpty()){
                if(contactCerts[0].isActive__c){
                    credentialStatus = 'Valid';
                    return credentialStatus;
                }else{
                    credentialStatus = 'Needs Renewal';
                    return credentialStatus;
                }
            }else{
                return credentialStatus;
            }
        }else{
            return credentialStatus;
        }
    }

}