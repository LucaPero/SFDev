public with sharing class CaseFileDownloadController {
    @AuraEnabled
    public static CaseFileWrapper downloadCaseFiles(Id caseId) {
        List<FileWrapper> files = new List<FileWrapper>();
        
        // Query Case to get Case Number
        Case caseRecord = [SELECT CaseNumber FROM Case WHERE Id = :caseId LIMIT 1];
        
        // Query ContentDocumentLink records associated with the Case
        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileType, ContentDocument.ContentSize, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :caseId
            ORDER BY SystemModstamp DESC
        ];
        
        // Store LatestPublishedVersionIds
        Set<Id> versionIds = new Set<Id>();
        for (ContentDocumentLink link : contentDocumentLinks) {
            versionIds.add(link.ContentDocument.LatestPublishedVersionId);
        }
        
        Map<Id, ContentVersion> contentVersions = new Map<Id, ContentVersion>(
            [SELECT Id, VersionData, FileExtension FROM ContentVersion WHERE Id IN :versionIds]
        );
        
        for (ContentDocumentLink link : contentDocumentLinks) {
            ContentVersion contentVersion = contentVersions.get(link.ContentDocument.LatestPublishedVersionId);
            if (contentVersion != null) {
                String base64Data = EncodingUtil.base64Encode(contentVersion.VersionData);
                String fileName = link.ContentDocument.Title + '.' + contentVersion.FileExtension;
                files.add(new FileWrapper(fileName, base64Data));
            }
        }
        
        return new CaseFileWrapper(caseRecord.CaseNumber, files);
    }
    
    public class FileWrapper {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String fileContent { get; set; }
        
        public FileWrapper(String fileName, String fileContent) {
            this.fileName = fileName;
            this.fileContent = fileContent;
        }
    }
    
    public class CaseFileWrapper {
        @AuraEnabled public String caseNumber { get; set; }
        @AuraEnabled public List<FileWrapper> files { get; set; }
        
        public CaseFileWrapper(String caseNumber, List<FileWrapper> files) {
            this.caseNumber = caseNumber;
            this.files = files;
        }
    }
}