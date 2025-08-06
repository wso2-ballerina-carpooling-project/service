import ballerina/http;
import ballerina/log;
import 'service.firebase as firebase;
import 'service.utility;


public function getFare() returns http:Response|error {

    string accessToken = checkpanic firebase:generateAccessToken();
    json|error queryResult = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "pricing",
            "defaultfare"
    );
    
    if queryResult is error {
        return utility:createErrorResponse(500,"Internal server error");
    }
    
    json price  = check queryResult.perkm.ensureType();
    return utility:createSuccessResponse(200,{price});
}


public function updateFare(http:Request req) returns http:Response|error {
    
    string accessToken = checkpanic firebase:generateAccessToken();
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    json newPrice = check payload.price;

    json|error queryResult = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "pricing",
            "defaultfare"
    );
    
    if queryResult is error {
        return utility:createErrorResponse(500,"Internal server error");
    }
    
    int price  =<int>newPrice;
    map<json> updateData  = {
        "perkm" : price
     }; 
    
    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "pricing",
            "defaultfare",
            updateData
        );
    
    if updateResult is error {
        log:printError("Error updating ride: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to book ride");
    }
    
    return utility:createSuccessResponse(200,{"updatedprice":newPrice});
     
}