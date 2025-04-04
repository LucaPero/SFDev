public with sharing class ContentController {
    @AuraEnabled
    public static void saveFile(String contentData, String title, String description, Id recId){
        if (contentData.startsWith('data:image/')) {
            contentData = contentData.split(',')[1];
        }
        ContentVersion cVersion = new ContentVersion();
        cVersion.ContentLocation = 'S';
        cVersion.PathOnClient = 'Content - '+System.now() +'.png';
        cVersion.Origin = 'H';
        cVersion.Title = title + ' - '+System.now();
        cVersion.VersionData = EncodingUtil.base64Decode(contentData);
        cVersion.Description = description;
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