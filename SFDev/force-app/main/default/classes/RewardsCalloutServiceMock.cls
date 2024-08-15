@isTest
public class RewardsCalloutServiceMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"message": "Success"}');
            res.setStatusCode(201);
            return res;
        }
}