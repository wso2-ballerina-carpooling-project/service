
import ballerina/http;
import 'service.firebase;
import 'service.auth;
import ballerina/io;
import 'service.Map;

string accessToken;

type PlaceInfo record {
    string description;
    string place_id;
};


function createSuccessResponse(int statusCode, json payload) returns http:Response {
    http:Response response = new;
    response.statusCode = statusCode;
    response.setJsonPayload(payload);
    return response;
}

// Helper function to create an error response
function createErrorResponse(int statusCode, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = statusCode;
    response.setJsonPayload({
        "status": "ERROR",
        "message": message
    });
    return response;
}  

service /api on new http:Listener(9090){
     function init() {
        // Initialize Firebase credentials
        accessToken = checkpanic firebase:generateAccessToken();
        io:print(accessToken);
    }

    resource function post register(@http:Payload json payload) returns http:Response|error {
        http:Response|error response= auth:register(payload,accessToken);
        return response;
    }
    resource function post login(@http:Payload json payload) returns http:Response|error {
        http:Response|error response = auth:login(payload,accessToken);
        return response;
    }   

    resource function get direction() {
        error? response = Map:getDirection();
    }

    resource function get searchLocation() {
    string searchQuery = "Colombo";
    io:println("Searching for places matching: '" + searchQuery + "'");
    
    PlaceInfo[]|error results = Map:searchSriLankaPlaces(searchQuery);
    
    if (results is PlaceInfo[]) {
        io:println("\nFound " + results.length().toString() + " places matching '" + searchQuery + "':");
        foreach PlaceInfo place in results {
            io:println("- " + place.description + " (ID: " + place.place_id + ")");
        }
        
        if (results.length() == 0) {
            io:println("No places found. This could be due to:");
            io:println("1. API key not having access to the Places API v1");
            io:println("2. No matching places in Sri Lanka");
            io:println("3. Network or API issues");
            io:println("\nImportant: You need to enable the 'Places API' in your Google Cloud Console");
            io:println("and ensure billing is set up for the project associated with your API key.");
        }
    } else {
        io:println("Error searching places: " + results.message());
    }
    }
 

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