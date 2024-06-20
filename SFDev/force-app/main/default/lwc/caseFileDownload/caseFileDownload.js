import { LightningElement, api } from 'lwc';
import downloadCaseFiles from '@salesforce/apex/CaseFileDownloadController.downloadCaseFiles';
import JSZipResource from '@salesforce/resourceUrl/JSZip';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CaseFileDownload extends LightningElement {
    @api recordId;
    zipInitialized = false;
    jsZip;

    @api
    invoke() {
        if (!this.zipInitialized) {
            loadScript(this, JSZipResource + '/jszip.min.js')
                .then(() => {
                    this.jsZip = new window.JSZip();
                    this.zipInitialized = true;
                    this.downloadFiles();
                })
                .catch(error => {
                    console.error('Error loading JSZip: ', error);
                    this.showToast('Error', 'Error loading JSZip library.', 'error');
                    this.closeQuickAction();
                });
        } else {
            this.downloadFiles();
        }
    }

    downloadFiles() {
        downloadCaseFiles({ caseId: this.recordId })
            .then(result => {
                if (result.files.length > 0) {
                    this.createZipFile(result.caseNumber, result.files);
                } else {
                    this.showToast('Info', 'No files to download.', 'info');
                    this.closeQuickAction();
                }
            })
            .catch(error => {
                console.error('Error downloading files: ', error);
                this.showToast('Error', 'Error downloading files.', 'error');
                this.closeQuickAction();
            });
    }

    createZipFile(caseNumber, files) {
        const folder = this.jsZip.folder(caseNumber);

        files.forEach(file => {
            folder.file(file.fileName, file.fileContent, { base64: true });
        });

        this.jsZip.generateAsync({ type: 'blob' })
            .then(content => {
                const element = document.createElement('a');
                element.href = URL.createObjectURL(content);
                element.download = caseNumber + '.zip';
                document.body.appendChild(element);
                element.click();
                document.body.removeChild(element);
                this.showToast('Success', 'Download was successful.', 'success');
                this.closeQuickAction();
            })
            .catch(error => {
                console.error('Error creating ZIP file: ', error);
                this.showToast('Error', 'Error creating ZIP file.', 'error');
                this.closeQuickAction();
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }

    closeQuickAction() {
        const closeEvent = new CustomEvent('close');
        this.dispatchEvent(closeEvent);
    }
}