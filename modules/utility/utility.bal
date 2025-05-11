import ballerina/http;

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