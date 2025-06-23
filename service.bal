import 'service.Map;
import 'service.auth;
import 'service.firebase;
import ballerina/http;
import ballerina/io;
import 'service.ride_management;



service /api on new http:Listener(9090) {
    resource function post register(@http:Payload json payload) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = auth:register(payload, accessToken);
        return response;
    }
    resource function post login(@http:Payload json payload) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = auth:login(payload, accessToken);
        return response;

    }
    resource function post postRide(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        io:print("POST /rides - Creating new ride");
        return ride_management:postARide(payload, accessToken, req);
    }
    resource function post getRide(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        io:print("POST /rides - Getting ride");
        return ride_management:getMyRides(accessToken, req);
    }

    resource function get direction() {
        error? response = Map:getDirection();
    }

     resource function post searchLocation(@http:Payload json payload) returns http:Response|error {
        // Safely extract the 'text' field from the payload
        string searchQuery = check payload.text.ensureType();
        io:println("Searching for places matching: '" + searchQuery + "'");

        // Call the function that uses Google Places API
        http:Response|error results = Map:searchSriLankaPlaces(searchQuery);
        return results;
    }

    // resource function get test() {
    //     string token = checkpanic auth:generateLoginToken().ensureType();
    //     io:println(token);
    //     jwt:Payload|error payload = auth:verifyToken(token);
    //     io:println(payload);
    // }

}





// import ballerina/http;
// import ballerina/log;
// import server.auth;
// // Protected API endpoint example
// service /api/v1 on new http:Listener(8080) {

//     // Public endpoint - login
//     resource function post login(@http:Payload json payload) returns http:Response|error {
//         string? email = check payload.email.ensureType();
//         string? password = check payload.password.ensureType();

//         if email is () || password is () {
//             return createErrorResponse(400, "Email and password are required");
//         }

//         // Here you would validate credentials from your database
//         // For this example, assume we found the user
//         string userId = "user123";
//         string role = "driver";

//         // Generate JWT token
//         string|error token = auth:generateJwtToken(userId, <string>email, role);

//         if token is error {
//             log:printError("Failed to generate token", token);
//             return createErrorResponse(500, "Authentication failed");
//         }

//         // Return token to client
//         return createSuccessResponse(200, {
//             "userId": userId,
//             "email": email,
//             "role": role,
//             "token": token
//         });
//     }

//     // Protected endpoint - requires authentication
//     resource function get profile(http:Request request) returns http:Response|error {
//         // Validate JWT token
//         boolean|error validation = auth:validateRequestToken(request);

//         if validation is error {
//             return createErrorResponse(401, validation.message());
//         }

//         boolean isValid = validation;

//         if !isValid {
//             return createErrorResponse(401, "Invalid authentication token");
//         }

//         // Here you would fetch the user's profile from your database
//         // For this example, we'll just return the information from the token
//         return createSuccessResponse(200, {
//             "profileComplete": true
//         });
//     }

//     // Protected endpoint with role check

// }

// // Helper functions for creating responses
// function createSuccessResponse(int statusCode, json data) returns http:Response {
//     http:Response response = new;
//     response.statusCode = statusCode;
//     response.setJsonPayload(data);
//     return response;
// }

// function createErrorResponse(int statusCode, string message) returns http:Response {
//     http:Response response = new;
//     response.statusCode = statusCode;
//     response.setJsonPayload({"error": message});
//     return response;
// }



