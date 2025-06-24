import 'service.Map;
import 'service.auth;
import 'service.firebase;
import 'service.ride_management;
import 'service.ride_management as ride_management1;
import 'service.utility;

import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/log;
import ballerina/time;

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
        io:print(payload.toJson());

        return ride_management:postARide(payload, accessToken, req);
    }

    resource function post getRide(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        io:print("POST /rides - Getting ride");
        return ride_management:getMyRides(accessToken, req);
    }

    resource function post search(http:Request req) returns http:Response|error {

        json|error payload = req.getJsonPayload();
        if payload is error {
            return utility:createErrorResponse(400, "Invalid JSON payload");
        }

        // Extract search parameters from JSON payload

        json dateJson = check payload.date;
        json time = check payload.time;
        boolean isWayToWork = check payload.waytowork;
        io:print(dateJson, time, isWayToWork);

        // Get access token from environment or configuration
        string accessToken = checkpanic firebase:generateAccessToken();

        http:Response|error result = ride_management1:findMatchingRides(
                accessToken,
                req,
                dateJson,
                time,
                isWayToWork
        );

        return result;
    }

   resource function post rides/book(http:Request req) returns http:Response|error {

    // Get JSON payload
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    // Extract rideId and waypoint from payload
    json rideIdJson = check payload.rideId;
    json waypointJson = check payload.waypoint;

    if rideIdJson is () || waypointJson is () {
        return utility:createErrorResponse(400, "Missing required fields: rideId, waypoint");
    }

    string rideId = rideIdJson.toString();
    string waypoint = waypointJson.toString();

    // Extract passenger ID from JWT token
    string|error authHeader = req.getHeader("Authorization");
    if authHeader is error {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    // Decode JWT token to extract passenger ID
    string jwtToken = authHeader.substring(7);

    // Verify JWT token
    jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
    if tokenPayload is error {
        log:printError("JWT decode error: " + tokenPayload.message());
        return utility:createErrorResponse(401, "Invalid token");
    }

    // Extract user ID from JWT payload (assuming it's in 'sub' or custom claims)
    string userId = <string>tokenPayload["id"];

    if userId is "" {
        return utility:createErrorResponse(401, "User ID not found in token");
    }

    log:printInfo(`Booking ride ${rideId} for passenger ${userId} with waypoint: ${waypoint}`);

    // Get Firebase access token
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        log:printError("Failed to generate access token", accessToken);
        return utility:createErrorResponse(500, "Authentication failed");
    }

    // Get the current ride document
    map<json> queryFilter = {"rideId": rideId};
    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
           "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    io:print(rideDoc);

    if rideDoc is error {
        if rideDoc.message().includes("Document not found") {
            return utility:createErrorResponse(404, "Ride not found");
        }
        log:printError("Error fetching ride: " + rideDoc.message());
        return utility:createErrorResponse(500, "Failed to fetch ride details");
    }

    if rideDoc.length() == 0 {
        log:printError("No document found with rideId: " + rideId);
        return utility:createErrorResponse(404, "Ride not found");
    }

    // Extract existing passengers array
    json[] existingPassengers = [];
    if rideDoc[0].hasKey("passengers") && rideDoc[0]["passengers"] is json[] {
        existingPassengers = <json[]>rideDoc[0]["passengers"];
    }

    // Check if passenger is already booked for this ride
    foreach json passenger in existingPassengers {
        if passenger is map<json> && passenger.hasKey("passengerId") {
            string existingPassengerId = passenger["passengerId"].toString();
            if existingPassengerId == userId {
                return utility:createErrorResponse(409, "Passenger already booked for this ride");
            }
        }
    }

    // Create new passenger object
    map<json> newPassenger = {
        "passengerId": userId,
        "waypoint": waypoint,
        "bookingTime": time:utcNow()[0],
        "status": "confirmed"
    };

    // Add new passenger to the array
    existingPassengers.push(newPassenger);

    // Get the actual document ID from the query result
    string actualDocumentId = <string>rideDoc[0]["id"];
    
    // FIXED: Use mergeFirestoreDocument instead of updateFirestoreDocument
    // This will only update the specified fields while preserving all other existing data
    map<json> updateData = {
        "passengers": existingPassengers,
        "updatedAt": time:utcNow()[0]
    };

    json|error updateResult = firebase:mergeFirestoreDocument(
        "carpooling-c6aa5", 
        accessToken, 
        "rides", 
        actualDocumentId, 
        updateData
    );

    // Alternative approach: Use updateFirestoreFields for explicit field control
    // json|error updateResult = firebase:updateFirestoreFields(
    //     "carpooling-c6aa5", 
    //     accessToken, 
    //     "rides", 
    //     actualDocumentId, 
    //     updateData
    // );

    // Another alternative: Use the array-specific update function
    // json|error updateResult = firebase:updateFirestoreArrayField(
    //     "carpooling-c6aa5", 
    //     accessToken, 
    //     "rides", 
    //     actualDocumentId, 
    //     "passengers",
    //     existingPassengers
    // );

    if updateResult is error {
        log:printError("Error updating ride: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to book ride");
    }

    // Return success response
    json successResponse = {
        "message": "Ride booked successfully",
        "rideId": rideId,
        "passengerId": userId,
        "waypoint": waypoint,
        "status": "confirmed",
        "bookingTime": time:utcNow()[0]
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    return response;
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

