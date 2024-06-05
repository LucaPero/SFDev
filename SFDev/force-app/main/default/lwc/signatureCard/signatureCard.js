import { LightningElement, api } from "lwc";
import saveSignature from '@salesforce/apex/SignatureController.saveSignature';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SignatureCard extends LightningElement {
    @api recordId;
    imgSrc;

    renderedCallback() {
        document.fonts.forEach((font) => {
            if (font.family === "Great Vibes" && font.status === "unloaded") {
                // Ensure that the font is loaded so that signature pad could use it.
                // If you are using a different font in your project, don't forget
                // to update the if-condition above to account for it.
                font.load();
            }
        });
    }

    async saveSignature() {
        const getBase64StringFromDataURL = (dataURL) =>
            dataURL.replace('data:', '').replace(/^.+,/, '');
        const pad = this.template.querySelector("c-signature-pad");
        if (pad) {
            const dataURL = pad.getSignature();
            if (dataURL) {
                // At this point you can consume the signature, for example by saving
                // it to disk or uploading it to a Salesforce org/record.
                // Here we just preview it in an image tag.
                this.imgSrc = dataURL;
                const convertedDataURI = getBase64StringFromDataURL(dataURL);

                await saveSignature({ signElement: convertedDataURI, recId: this.recordId })
                    .then(result => {
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Success',
                                message: 'Signature Image saved in record',
                                variant: 'success',
                            }),
                        );
                    })
                    .catch(error => {
                        //show error message
                        this.dispatchEvent(
                            new ShowToastEvent({
                                title: 'Error uploading signature in Salesforce record',
                                message: error.body.message,
                                variant: 'error',
                            }),
                        );
                    });
            }
        }
    }

    clearSignature() {
        const pad = this.template.querySelector("c-signature-pad");
        if (pad) {
            pad.clearSignature();
        }

        this.imgSrc = null;
    }
}