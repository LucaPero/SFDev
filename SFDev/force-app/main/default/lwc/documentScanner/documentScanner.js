import { LightningElement, api, track } from "lwc";
import { getDocumentScanner } from "lightning/mobileCapabilities";
import createGeneration from '@salesforce/apex/ModelsAPI.createGeneration';
import saveFile from '@salesforce/apex/ContentController.saveFile';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class DocumentScanner extends LightningElement {
    // Scan results (if any)
    scannerError;
    scannedDocument;
    @api recordId;
    workingMessage = 'Processing your document, please wait...';

    prompt = 'As a Support Agent and Customer Service Director, your job is to generate a Case description(no more than 80 words, category and suggested actions around next steps, return the result in a JSON format with three properties, category, description, suggestedActions(list format) and keyInsights(this field will contain key insights or trends from the document that may be relevant), considering the following text:\n';
    response = '';

    get isWorkingOnResponse(){
        return this.response === this.workingMessage;
    }

    get isTextGenerationCompleted(){
        return this.response !== this.workingMessage &&  this.response !== '';
    }

    get isWorkingOnError(){
        return this.scannerError !== '';
    }

    handleScanFromCameraClick() {
        this.scanDocument("DEVICE_CAMERA");
    }

    handleScanFromPhotoLibraryClick() {
        this.scanDocument("PHOTO_LIBRARY");
    }

    scanDocument(imageSource) {
        // Clear previous results / errors
        this.resetScanResults();

        // Main document scan cycle
        const myScanner = getDocumentScanner();
        if (myScanner.isAvailable()) {
            const options = {
                imageSource: imageSource,
                scriptHint: "LATIN",
                returnImageBytes: true,
                extractEntities: true,
                entityExtractionLanguageCode: "NL",
            };

            // Perform document scan
            myScanner
                .scan(options)
                .then((results) => {
                    // Do something with the results
                    this.processScannedDocuments(results);
                })
                .catch((error) => {
                    // Handle errors
                    this.scannerError =
                        "Error code: " + error.code + "\nError message: " + error.message;
                });
        } else {
            // Scanner not available
            this.scannerError =
                "Problem initiating scan. Are you using a mobile device?";
        }
    }

    resetScanResults() {
        this.scannedDocument = null;
        this.scannerError = null;
    }

    async processScannedDocuments(documents) {
        this.scannedDocument = documents[0];
        this.prompt += this.scannedDocument.text;
        this.response = this.workingMessage;
        await createGeneration({ prompt: this.prompt })
            .then(result => {
                this.response = JSON.parse(result);
                this.error = undefined;
            })
            .catch(error => {
                this.response = 'Error';
                this.error = error;
            })
        // And this is where you take over; process results as desired
    }

    // Build an annotation overlay graphic, to display on top of the scanned image
    addImageHighlights(event) {
        const textBlocks = this.scannedDocument?.blocks;
        if (!textBlocks) {
            return;
        }

        const img = event.srcElement;
        const cWidth = img.clientWidth;
        const cHeight = img.clientHeight;
        const nWidth = img.naturalWidth;
        const nHeight = img.naturalHeight;
        const width = Math.min(cWidth, nWidth);
        const height = Math.min(cHeight, nHeight);

        let svg =
            ``;
        textBlocks.forEach((block) =>
            block.lines.forEach((line) =>
                line.elements.forEach((element) => {
                    const frame = element.frame;
                    svg +=
                        ``;
                })
            )
        );
        svg += "";

        // Manually attach the overlay SVG to the LWC DOM to render it
        if (this.template.querySelector(".contour")) {
            this.template.querySelector(".contour").innerHTML = svg;
        }
    }

    handleSubmit(){

        saveFile({
            contentData: this.scannedDocument.imageBytes,
            title: this.response.category,
            description: this.response.description,
            recId: this.recordId
        })
        .then(result => {
            console.log(result);

            const evt = new ShowToastEvent({
                title: 'File saved successfully',
                message: 'The file has been saved to your case',
                variant: 'success'
            });
            this.dispatchEvent(evt);
        })
    }
}