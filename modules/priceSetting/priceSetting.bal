import ballerina/http;
import ballerina/log;
import 'service.firebase as firebase;
import 'service.utility;


public function getFare() returns http:Response|error {
    // Attempt to get the document from the 'Metadata' collection with the
    string accessToken = checkpanic firebase:generateAccessToken();
    json|error queryResult = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            "sys-data"
    );
    if queryResult is error {
        return utility:createErrorResponse(500,"Internal server error");
    }
    json price  = check queryResult.perKm.ensureType();
    return utility:createSuccessResponse(200,{price});
}


public function updateFare(http:Request req) returns http:Response|error {
    // The payload should be in the format: { "perKm": 100 }
    string accessToken = checkpanic firebase:generateAccessToken();
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    json newPrice = check payload.price;

    json|error queryResult = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            "sys-data"
    );
    if queryResult is error {
        return utility:createErrorResponse(500,"Internal server error");
    }
    int price  =<int>newPrice;
    map<json> updateData  = {
        "perKm" : price
     };
    
    
    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "metadata",
            "sys-data",
            updateData
        );
     if updateResult is error {
        log:printError("Error updating ride: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to book ride");
    }
    return utility:createSuccessResponse(200,{"updatedprice":newPrice});
     
}