import ballerina/http;



//final string FCM_ENDPOINT = "https://fcm.googleapis.com/v1/projects/carpooling-c6aa5/messages:send"; 
public function createErrorResponse(int status, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload({"message": message});
    return response;
}

// Utility function for success responses
public  function createSuccessResponse(int status, json payload) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(payload);
    return response;
}



