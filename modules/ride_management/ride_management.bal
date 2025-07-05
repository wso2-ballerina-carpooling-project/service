import 'service.firebase as firebase;
import 'service.utility as utility;

import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

configurable string publicKey = ?;

// Define ride data types
type RideData record {
    string startLocation;
    string endLocation;
    boolean waytowork;
    string date;
    string time;
    RouteInfo route;
};

type RouteInfo record {
    int index;
    string duration;
    string distance;
    LatLng[] polyline;
};

type LatLng record {
    decimal latitude;
    decimal longitude;
};

public function verifyToken(string jwtToken) returns jwt:Payload|error {

    if jwtToken.trim() == "" {
        return error("JWT token is empty or null");
    }

    jwt:ValidatorConfig validatorConfig = {
        issuer: "CarPool",
        audience: "CarPool-App",
        signatureConfig: {
            certFile: publicKey
        }
    };

    jwt:Payload|error payload = jwt:validate(jwtToken, validatorConfig);

    if payload is error {
        log:printError("JWT validation failed", payload);
        return error("Invalid or expired token");
    }

    jwt:Payload validPayload = payload;

    if validPayload.exp is int {
        int currentTime = time:utcNow()[0];
        if currentTime > validPayload.exp {
            return error("Token has expired");
        }
    }

    if validPayload.iss != "CarPool" {
        return error("Invalid token issuer");
    }

    if validPayload.aud != "CarPool-App" {
        return error("Invalid token audience");
    }

    return validPayload;
}

public function postARide(@http:Payload json payload, string accessToken, http:Request req) returns http:Response {

    // Get authorization header
    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    // Extract JWT token (remove "Bearer " prefix)
    string jwtToken = authHeader.substring(7);

    // Verify JWT token
    jwt:Payload|error tokenPayload = verifyToken(jwtToken);
    if tokenPayload is error {
        log:printError("Token verification failed", tokenPayload);
        return utility:createErrorResponse(401, "Invalid or expired token");
    }
    io:print(tokenPayload);

    // Extract user info from token
    string userId = <string>tokenPayload["id"];
    string userRole = <string>tokenPayload["role"];
    string userStatus = <string>tokenPayload["status"];

    if userRole != "admin" && userStatus != "approved" {
        return utility:createErrorResponse(403, "Your account is not approved to post rides");
    }

    // Validate ride data
    RideData|error rideData = payload.cloneWithType(RideData);
    if rideData is error {
        log:printError("Invalid ride data format", rideData);
        return utility:createErrorResponse(400, "Invalid ride data format");
    }

    string rideId = uuid:createType1AsString();
    string currentTime = time:utcNow().toString();

    json|error queryResult = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            userId
    );

    int seat = 0;

    if (queryResult is json) {
        // First check if queryResult is a map<json>
        if (queryResult is map<json>) {
            // Then safely extract the nested values
            json driverDetailsValue = queryResult["driverDetails"];
            if (driverDetailsValue is map<json>) {
                json seatingCapacityValue = driverDetailsValue["seatingCapacity"];
                if (seatingCapacityValue is int) {
                    seat = seatingCapacityValue;
                    log:printInfo("Seating capacity: " + seat.toString());
                } else {
                    log:printError("seatingCapacity is not an integer");
                }
            } else {
                log:printError("driverDetails is not a map");
            }
        } else {
            log:printError("Query result is not a map");
        }
    } else {
        log:printError("Error getting document: " + queryResult.message());
    }

    map<json> rideDocument = {
        "rideId": rideId,
        "driverId": userId,
        "startLocation": rideData.startLocation,
        "endLocation": rideData.endLocation,
        "date": rideData.date,
        "waytowork": rideData.waytowork,
        "seat": seat,
        "time": rideData.time,
        "route": {
            "index": rideData.route.index,
            "duration": rideData.route.duration,
            "distance": rideData.route.distance,
            "polyline": rideData.route.polyline.toJson()
        },
        "status": "active",
        "createdAt": currentTime,
        "updatedAt": currentTime,
        "passengers": []
    };

    // Store ride in Firestore
    json|error createResult = firebase:createFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            rideDocument
    );

    if createResult is error {
        log:printError("Failed to create ride", createResult);
        return utility:createErrorResponse(500, "Failed to post ride");
    }

    log:printInfo("Ride posted successfully with ID: " + rideId);

    return utility:createSuccessResponse(201, {
                                                  "message": "Ride posted successfully",
                                                  "rideId": rideId,
                                                  "ride": rideDocument
                                              });
}

// Get rides function
public function getRides(string accessToken, http:Request req, string? origin = (), string? destination = (), string? date = ()) returns http:Response|error {
    // Get authorization header
    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    // Extract and verify JWT token
    string jwtToken = authHeader.substring(7);
    jwt:Payload|error tokenPayload = verifyToken(jwtToken);
    if tokenPayload is error {
        return utility:createErrorResponse(401, "Invalid or expired token");
    }

    // Build query filter
    map<json> queryFilter = {"status": "active"};

    if origin is string && origin != "" {
        queryFilter["pickupLocation"] = origin;
    }
    if destination is string && destination != "" {
        queryFilter["dropoffLocation"] = destination;
    }
    if date is string && date != "" {
        queryFilter["date"] = date;
    }

    // Query rides from Firestore
    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    if queryResult is error {
        log:printError("Failed to fetch rides", queryResult);
        return utility:createErrorResponse(500, "Failed to fetch rides");
    }

    return utility:createSuccessResponse(200, {
                                                  "rides": queryResult,
                                                  "count": queryResult.length()
                                              });
}

// Get user's rides
public function getMyRides(string accessToken, http:Request req) returns http:Response|error {
    // Get authorization header
    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    // Extract and verify JWT token
    string jwtToken = authHeader.substring(7);
    jwt:Payload|error tokenPayload = verifyToken(jwtToken);
    if tokenPayload is error {
        return utility:createErrorResponse(401, "Invalid or expired token");
    }

    // Extract user info from token
    string userId = <string>tokenPayload["id"];
    io:print(userId);

    // Query user's rides
    map<json> queryFilter = {"driverId": userId};
    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );
    io:print(queryResult);

    if queryResult is error {
        // log:printError("Failed to fetch user rides", queryResult);
        return utility:createErrorResponse(500, "Failed to fetch your rides");
    }

    return utility:createSuccessResponse(200, {
                                                  "rides": queryResult,
                                                  "count": queryResult.length()
                                              });
}

public function findMatchingRides(
        string accessToken,
        http:Request req,
        json date,
        json time,
        boolean isWayToWork

) returns http:Response|error {

    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    string jwtToken = authHeader.substring(7);
    jwt:Payload|error tokenPayload = verifyToken(jwtToken);
    if tokenPayload is error {
        return utility:createErrorResponse(401, "Invalid or expired token");
    }

    map<json> queryFilter = {
        "status": "active",
        "waytowork": isWayToWork,
        "date": date,
        "time": time
    };

    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    io:print(queryResult);

    if queryResult is error {
        log:printError("Failed to fetch rides", queryResult);
        return utility:createErrorResponse(500, "Failed to fetch rides");
    }

    map<json>[] newData = [];
    foreach var item in queryResult {
        if (<int>item["seat"] > 0) {
            newData.push(item);
        }
    }

    return utility:createSuccessResponse(200, {
                                                  "rides": newData,
                                                  "count": queryResult.length()
                                              });

}

public function book(http:Request req) returns http:Response|error {
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    json rideIdJson = check payload.rideId;
    json waypointJson = check payload.waypoint;

    if rideIdJson is () || waypointJson is () {
        return utility:createErrorResponse(400, "Missing required fields: rideId, waypoint");
    }

    string rideId = rideIdJson.toString();
    string waypoint = waypointJson.toString();

    string|error authHeader = req.getHeader("Authorization");
    if authHeader is error {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    string jwtToken = authHeader.substring(7);

    jwt:Payload|error tokenPayload = verifyToken(jwtToken);
    if tokenPayload is error {
        log:printError("JWT decode error: " + tokenPayload.message());
        return utility:createErrorResponse(401, "Invalid token");
    }

    string userId = <string>tokenPayload["id"];

    if userId is "" {
        return utility:createErrorResponse(401, "User ID not found in token");
    }

    log:printInfo(`Booking ride ${rideId} for passenger ${userId} with waypoint: ${waypoint}`);

    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        log:printError("Failed to generate access token", accessToken);
        return utility:createErrorResponse(500, "Authentication failed");
    }

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
    string driver = rideDoc[0]["driverId"].toString();
    io:println(driver);
    json[] existingPassengers = [];
    if rideDoc[0].hasKey("passengers") && rideDoc[0]["passengers"] is json[] {
        existingPassengers = <json[]>rideDoc[0]["passengers"];
    }

    foreach json passenger in existingPassengers {
        if passenger is map<json> && passenger.hasKey("passengerId") {
            string existingPassengerId = passenger["passengerId"].toString();
            if existingPassengerId == userId {
                return utility:createErrorResponse(409, "Passenger already booked for this ride");
            }
        }
    }
    int seat = <int>rideDoc[0]["seat"];
    int newSeat = seat - 1;

    map<json> newPassenger = {
        "passengerId": userId,
        "waypoint": waypoint,
        "bookingTime": time:utcNow()[0],
        "status": "confirmed"
    };

    existingPassengers.push(newPassenger);

    string actualDocumentId = <string>rideDoc[0]["id"];

    map<json> updateData = {
        "passengers": existingPassengers,
        "seat": newSeat,
        "updatedAt": time:utcNow()[0]
    };

    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            actualDocumentId,
            updateData
        );

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

public function getCompletedRide(http:Request req) returns http:Response|error{
    string|error authHeader = req.getHeader("Authorization");
    if authHeader is error {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    string jwtToken = authHeader.substring(7);

    jwt:Payload|error tokenPayload = verifyToken(jwtToken);
    if tokenPayload is error {
        log:printError("JWT decode error: " + tokenPayload.message());
        return utility:createErrorResponse(401, "Invalid token");
    }

    string userId = <string>tokenPayload["id"];

    if userId is "" {
        return utility:createErrorResponse(401, "User ID not found in token");
    }
    string accessToken = checkpanic firebase:generateAccessToken();
    map<json> queryFilter = {"driverId": userId,"status":"completed"};
    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );
    io:print(queryResult);
    return utility:createErrorResponse(401, "User ID not found in token");
}

