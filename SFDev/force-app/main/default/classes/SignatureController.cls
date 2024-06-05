
public with sharing class SignatureController {
    @AuraEnabled
    public static void saveSignature(String signElement,Id recId){
        ContentVersion cVersion = new ContentVersion();
        cVersion.ContentLocation = 'S';
        cVersion.PathOnClient = 'Signature-'+System.now() +'.png';
        cVersion.Origin = 'H';
        cVersion.Title = 'Signature-'+recId+'-'+System.now() +'.png';
        cVersion.VersionData = EncodingUtil.base64Decode(signElement);
        Insert cVersion;
        
        //Get the Uploaded doc ContentDocumentId
        Id conDocument = [SELECT ContentDocumentId FROM ContentVersion WHERE Id =:cVersion.Id].ContentDocumentId;
        
        //Insert ContentDocumentLink to share 
        ContentDocumentLink cDocLink = new ContentDocumentLink();
        cDocLink.ContentDocumentId = conDocument;
        cDocLink.LinkedEntityId = recId;
        cDocLink.ShareType = 'I';
        cDocLink.Visibility = 'AllUsers';
        Insert cDocLink;
    }
}