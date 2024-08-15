public class RewardsCalloutService{

    public static Integer submitUsersForRewardCallout(String jsonBody) {
        //Set Endpoint from Named Credential
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:IntegrationSB__BalancedLiving/rewards');
        req.setMethod('POST');
        req.setBody(jsonBody);
        //Make HTTP Callout
        Integer statusCode;
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
            statusCode = res.getStatusCode();
            System.debug('Response Status: ' + statusCode);
            System.debug('Response Body: ' + res.getBody());
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            statusCode = 500; // Internal Server Error
        }
        return statusCode;
    }
}