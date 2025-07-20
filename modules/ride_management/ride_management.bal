import 'service.firebase as firebase;
import 'service.notification;
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
        "date": date
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
    json waypointlatlan = check payload.waypointLN;
    json cost = check payload.cost;

    if rideIdJson is () || waypointJson is () {
        return utility:createErrorResponse(400, "Missing required fields: rideId, waypoint");
    }

    string rideId = rideIdJson.toString();
    string waypoint = waypointJson.toString();

    decimal? waypointLat = ();
    decimal? waypointLng = ();

    if waypointlatlan is json[] {
        // Handle array format [latitude, longitude]
        if waypointlatlan.length() >= 2 {
            waypointLat = <decimal>waypointlatlan[0];
            waypointLng = <decimal>waypointlatlan[1];
        }
    }

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

    map<json> waypointData = {};
    io:print(waypointLat);

    waypointData["latitude"] = waypointLat.toJson();
    waypointData["longitude"] = waypointLng.toJson();

    map<json> newPassenger = {
        "passengerId": userId,
        "waypoint": waypoint,
        "cost": cost,
        "bookingTime": time:utcNow()[0],
        "status": "confirmed"
    };
    newPassenger["waypointLN"] = waypointData;

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

    map<json>|error userDoc = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            driver
    );
    if (userDoc is error) {

    } else {
        string fcm = checkpanic userDoc.fcm.ensureType();
        string currentTime = time:utcNow().toString();
        map<string> data = {
            "callId": "No data"
        };
        string rideDate = check rideDoc[0]["date"].ensureType();
        string massage = string `New booking for your ride shedule for ${rideDate}`;
        string|error response = notification:sendFCMNotification(fcm, "New Booking", "New ride booking for your ride", "carpooling-c6aa5", data);
        map<json> notifyData = {
            "user": driver,
            "title": "New Ride Booking",
            "massage": massage,
            "isread": false,
            "createdAt": currentTime
        };
        json|error createResult = firebase:createFirestoreDocument(
                "carpooling-c6aa5",
                accessToken,
                "notification",
                notifyData
        );
        io:print(createResult);
        io:print(response);
    }

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    return response;

}

public function getCompleteRide(http:Request req) returns http:Response|error {
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
    map<json> queryFilter = {"driverId": userId, "status": "completed"};
    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );
    if queryResult is error {
        // log:printError("Failed to fetch user rides", queryResult);
        return utility:createErrorResponse(500, "No completed rides");
    }
    return utility:createSuccessResponse(200, {"rides": queryResult});
}

public function getOngoingRide(http:Request req) returns http:Response|error {
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
    map<json> queryFilter = {"driverId": userId, "status": "active"};
    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );
    if queryResult is error {
        // log:printError("Failed to fetch user rides", queryResult);
        return utility:createErrorResponse(500, "No completed rides");
    }
    return utility:createSuccessResponse(200, {"rides": queryResult});
}

public function getCancelRide(http:Request req) returns http:Response|error {
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
    map<json> queryFilter = {"driverId": userId, "status": "cancel"};
    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );
    if queryResult is error {
        // log:printError("Failed to fetch user rides", queryResult);
        return utility:createErrorResponse(500, "No completed rides");
    }
    return utility:createSuccessResponse(200, {"rides": queryResult});
}

public function getStartRide(string accessToken, http:Request req) returns http:Response|error {
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

    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    json rideIdJson = check payload.rideId;
    string rideId = rideIdJson.toString();
    io:print(rideId);
    map<json> queryFilter = {"rideId": rideId};
    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
        );
    if rideDoc is error {
        // log:printError("Failed to fetch user rides", queryResult);
        return utility:createErrorResponse(500, "No completed rides");
    }
    // io:print({"rides":rideDoc});
    return utility:createSuccessResponse(200, {"rides": rideDoc});
}

public function getPassengerOngoing(http:Request req) returns http:Response|error {
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
    io:print(userId);

    map<json> queryFilter = {"status": "active"};
    string accessToken = checkpanic firebase:generateAccessToken();

    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

     map<json> queryFilter2 = {"status": "start"};

    map<json>[]|error rideDoc2 = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        accessToken,
        "rides",
        queryFilter2
    );

    if rideDoc is error {
        return utility:createErrorResponse(500, "Failed to fetch rides");
    }
    if rideDoc2 is error {
        return utility:createErrorResponse(500, "Failed to fetch rides");
    }
    // io:print(rideDoc2);

    // Filter rides where user is a confirmed passenger
    map<json>[] userRides = [];

    foreach map<json> ride in rideDoc {
        // Check if passengers array exists
        if ride.hasKey("passengers") {
            json passengersJson = ride["passengers"];

            // Convert to array if it's a valid array
            if passengersJson is json[] {
                foreach json passenger in passengersJson {
                    if passenger is map<json> {
                        // Check if this passenger matches the user and has confirmed status
                        if passenger.hasKey("passengerId") && passenger.hasKey("status") {
                            string passengerIdStr = passenger["passengerId"].toString();
                            string statusStr = passenger["status"].toString();

                            if passengerIdStr == userId && statusStr == "confirmed" {
                                userRides.push(ride);
                                break; // Found the user in this ride, no need to check other passengers
                            }
                        }
                    }
                }
            }
        }
    }
    io:print(userRides.length());
    foreach map<json> ride in rideDoc2 {
        // Check if passengers array exists
        if ride.hasKey("passengers") {
            json passengersJson = ride["passengers"];

            // Convert to array if it's a valid array
            if passengersJson is json[] {
                foreach json passenger in passengersJson {
                    if passenger is map<json> {
                        // Check if this passenger matches the user and has confirmed status
                        if passenger.hasKey("passengerId") && passenger.hasKey("status") {
                            string passengerIdStr = passenger["passengerId"].toString();
                            string statusStr = passenger["status"].toString();
                            io:print("methanata awa");
                            if passengerIdStr == userId && statusStr == "confirmed" {
                                io:print("one found");
                                userRides.push(ride);
                                break; // Found the user in this ride, no need to check other passengers
                            }
                        }
                    }
                }
            }
        }
    }

    if userRides.length() == 0 {
        return utility:createSuccessResponse(200, {
                                                      "message": "No ongoing rides found for this passenger",
                                                      "rideDoc": []
                                                  });
    }

    return utility:createSuccessResponse(200, {
                                                  "message": string `Found ${userRides.length()} ongoing ride(s)`,
                                                  "rideDoc": userRides
                                              });
}

public function getPassengerCancel(http:Request req) returns http:Response|error {
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
    io:print(userId);

    map<json> queryFilter = {"status": "active"};
    string accessToken = checkpanic firebase:generateAccessToken();

    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    if rideDoc is error {
        return utility:createErrorResponse(500, "Failed to fetch rides");
    }

    // Filter rides where user is a confirmed passenger
    map<json>[] userRides = [];

    foreach map<json> ride in rideDoc {
        // Check if passengers array exists
        if ride.hasKey("passengers") {
            json passengersJson = ride["passengers"];

            // Convert to array if it's a valid array
            if passengersJson is json[] {
                foreach json passenger in passengersJson {
                    if passenger is map<json> {
                        // Check if this passenger matches the user and has confirmed status
                        if passenger.hasKey("passengerId") && passenger.hasKey("status") {
                            string passengerIdStr = passenger["passengerId"].toString();
                            string statusStr = passenger["status"].toString();

                            if passengerIdStr == userId && statusStr == "cancel" {
                                userRides.push(ride);
                                break; // Found the user in this ride, no need to check other passengers
                            }
                        }
                    }
                }
            }
        }
    }

    if userRides.length() == 0 {
        return utility:createSuccessResponse(200, {
                                                      "message": "No cancel rides found for this passenger",
                                                      "rideDoc": []
                                                  });
    }

    return utility:createSuccessResponse(200, {
                                                  "message": string `Found ${userRides.length()} cacel ride(s)`,
                                                  "rideDoc": userRides
                                              });
}

public function getPassengerComplete(http:Request req) returns http:Response|error {
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
    io:print(userId);

    map<json> queryFilter = {"status": "complete"};
    string accessToken = checkpanic firebase:generateAccessToken();

    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    if rideDoc is error {
        return utility:createErrorResponse(500, "Failed to fetch rides");
    }

    // Filter rides where user is a confirmed passenger
    map<json>[] userRides = [];

    foreach map<json> ride in rideDoc {
        // Check if passengers array exists
        if ride.hasKey("passengers") {
            json passengersJson = ride["passengers"];

            // Convert to array if it's a valid array
            if passengersJson is json[] {
                foreach json passenger in passengersJson {
                    if passenger is map<json> {
                        // Check if this passenger matches the user and has confirmed status
                        if passenger.hasKey("passengerId") && passenger.hasKey("status") {
                            string passengerIdStr = passenger["passengerId"].toString();
                            string statusStr = passenger["status"].toString();

                            if passengerIdStr == userId && statusStr == "confirmed" {
                                userRides.push(ride);
                                break; // Found the user in this ride, no need to check other passengers
                            }
                        }
                    }
                }
            }
        }
    }

    if userRides.length() == 0 {
        return utility:createSuccessResponse(200, {
                                                      "message": "No completed rides found for this passenger",
                                                      "rideDoc": []
                                                  });
    }

    return utility:createSuccessResponse(200, {
                                                  "message": string `Found ${userRides.length()} completed ride(s)`,
                                                  "rideDoc": userRides
                                              });
}

public function cancelPassengerBooking(http:Request req) returns http:Response|error {
    // Get and verify authorization header
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

    // Get request body to extract rideId
    json|error requestBody = req.getJsonPayload();
    if requestBody is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    map<json> requestData = <map<json>>requestBody;
    if !requestData.hasKey("rideId") {
        return utility:createErrorResponse(400, "rideId is required");
    }

    string rideId = requestData["rideId"].toString();

    // Generate access token for Firebase
    string accessToken = checkpanic firebase:generateAccessToken();
    map<json> queryFilter = {"rideId": rideId};
    // First, get the specific ride document
    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    if rideDoc is error {
        return utility:createErrorResponse(500, "Failed to fetch ride document");
    }

    // Check if the ride exists and is active
    if !rideDoc[0].hasKey("status") || rideDoc[0]["status"].toString() != "active" {
        return utility:createErrorResponse(400, "Ride is not active or does not exist");
    }

    // Check if passengers array exists
    if !rideDoc[0].hasKey("passengers") {
        return utility:createErrorResponse(400, "No passengers found in this ride");
    }

    json passengersJson = rideDoc[0]["passengers"];
    if !(passengersJson is json[]) {
        return utility:createErrorResponse(400, "Invalid passengers data structure");
    }

    json[] passengers = <json[]>passengersJson;
    boolean passengerFound = false;
    boolean alreadyCancelled = false;

    // Find and update the passenger status
    foreach int i in 0 ..< passengers.length() {
        json passenger = passengers[i];
        if passenger is map<json> {
            if passenger.hasKey("passengerId") && passenger["passengerId"].toString() == userId {
                passengerFound = true;
                string currentStatus = passenger["status"].toString();

                if currentStatus == "cancel" {
                    alreadyCancelled = true;
                    break;
                } else if currentStatus == "confirmed" {
                    // Update passenger status to cancel
                    map<json> updatedPassenger = passenger.clone();
                    updatedPassenger["status"] = "cancel";
                    passengers[i] = updatedPassenger;
                    break;
                } else {
                    return utility:createErrorResponse(400, "Cannot cancel - passenger status is not confirmed");
                }
            }
        }
    }

    if !passengerFound {
        return utility:createErrorResponse(404, "Passenger not found in this ride");
    }

    if alreadyCancelled {
        return utility:createErrorResponse(400, "Ride booking is already cancelled");
    }

    // Get current seat count and increment by 1
    int currentSeat = 0;
    if rideDoc[0].hasKey("seat") {
        json seatJson = rideDoc[0]["seat"];
        if seatJson is int {
            currentSeat = seatJson;
        }
    }
    int newSeatCount = currentSeat + 1;

    string actualDocumentId = <string>rideDoc[0]["id"];

    // Prepare update data
    map<json> updateData = {
        "passengers": passengers,
        "seat": newSeatCount,
        "updatedAt": time:utcNow()[0].toString() + "Z"
    };

    // Update the ride document
    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            actualDocumentId,
            updateData
    );

    string driverId = check rideDoc[0]["driverId"].ensureType();
    json|error queryResult = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            driverId
    );

    if !(queryResult is error) {
        string fcm = check queryResult.fcm.ensureType();
        string|error notifires = notification:sendFCMNotification(fcm, "Booking Cancellation", "Passenger cancel booking.", "carpooling-c6aa5");
        io:print(notifires);
        string currentTime = time:utcNow().toString();
        map<json> notifyData = {
            "user": driverId,
            "title": "Booking Cancel",
            "massage": "Booked seat cancel by passenger",
            "isread": false,
            "createdAt": currentTime
        };
        json|error createResult = firebase:createFirestoreDocument(
                "carpooling-c6aa5",
                accessToken,
                "notification",
                notifyData
                    );
        io:print(createResult);

    }

    if updateResult is error {
        log:printError("Failed to update ride document: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to cancel ride booking");
    }

    return utility:createSuccessResponse(200, {
                                                  "message": "Ride booking cancelled successfully",
                                                  "rideId": rideId,
                                                  "newSeatCount": newSeatCount
                                              });
}

public function cancelDriverRide(http:Request req) returns http:Response|error {
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    string rideId = check payload.rideId;
    io:print(rideId);
    string reason = check payload.reason;
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }
    map<json>|error rideDoc = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            rideId
            );
    if rideDoc is error {
        if rideDoc.message().includes("Document not found") {
            return utility:createErrorResponse(404, "Ride not found");
        }
        return utility:createErrorResponse(500, "Failed to fetch ride details");
    }

    if rideDoc.length() == 0 {
        return utility:createErrorResponse(404, "Ride not found");
    }

    string actualDocumentId = <string>rideDoc["id"];

    map<json> updateData = {
        "status": "cancel",
        "reason": reason
    };
    json|error updateResult = firebase:mergeFirestoreDocument(
                "carpooling-c6aa5",
            accessToken,
            "rides",
            actualDocumentId,
            updateData
        );

    if updateResult is error {
        return utility:createErrorResponse(500, "Failed to book ride");
    }
    string rideDate = check rideDoc["date"].ensureType();
    string message = string `Your booked ride was cancelled due to the ${reason}. Ride that booked for ${rideDate}`;
    json passengersJson = rideDoc["passengers"];
    if (passengersJson is json[]) {
        json[] passengers = <json[]>passengersJson;
        foreach int i in 0 ..< passengers.length() {
            json passenger = passengers[i];
            if passenger is map<json> {
                if passenger.hasKey("passengerId") {
                    string PID = check passenger["passengerId"].ensureType();
                    map<json>|error passengerDoc = firebase:getFirestoreDocumentById(
                                "carpooling-c6aa5",
                            accessToken,
                            "users",
                            PID
                        );
                    if (passengerDoc is error) {
                        break;
                    }

                    string number = check passengerDoc["phone"].ensureType();
                    string internationalNumber1 = "+94" + number.substring(1);
                    error? response = notification:sendsms(internationalNumber1, message);
                    io:print(response);

                    string fcm = passengerDoc["fcm"].toString();
                    string|error notifires = notification:sendFCMNotification(fcm, "Ride Cancellation", message, "carpooling-c6aa5");
                    io:print(notifires);
                    string currentTime = time:utcNow().toString();
                    map<json> notifyData = {
                        "user": PID,
                        "title": "Ride Cancel",
                        "massage": message,
                        "isread": false,
                        "createdAt": currentTime
                    };
                    json|error createResult = firebase:createFirestoreDocument(
                            "carpooling-c6aa5",
                            accessToken,
                            "notification",
                            notifyData
                    );
                    io:print(createResult);
                }
            }
        }
    }
    json successResponse = {
        "message": "Ride cancel successfully",
        "rideId": rideId,
        "status": "cancel"
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    return response;

}

public function startride(http:Request req) returns http:Response|error {
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    string rideId = check payload.rideId;
    io:print(rideId);
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }

     map<json> queryFilter = {"rideId": rideId};
    // First, get the specific ride document
    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    if rideDoc is error {
        return utility:createErrorResponse(500, "Failed to fetch ride document");
    }

    if rideDoc.length() == 0 {
        return utility:createErrorResponse(404, "Ride not found");
    }

    string actualDocumentId = <string>rideDoc[0]["id"];

    map<json> updateData = {
        "status": "start"
    };
    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            actualDocumentId,
            updateData
        );

    if updateResult is error {
        return utility:createErrorResponse(500, "Failed to start ride");
    }
    string message = string `Your booked ride was started. Be ready`;
    json passengersJson = rideDoc[0]["passengers"];
    if (passengersJson is json[]) {
        json[] passengers = <json[]>passengersJson;
        foreach int i in 0 ..< passengers.length() {
            json passenger = passengers[i];
            if passenger is map<json> {
                if passenger.hasKey("passengerId") {
                    string PID = check passenger["passengerId"].ensureType();
                    map<json>|error passengerDoc = firebase:getFirestoreDocumentById(
                            "carpooling-c6aa5",
                            accessToken,
                            "users",
                            PID
                        );
                    if (passengerDoc is error) {
                        break;
                    }

                    string number = check passengerDoc["phone"].ensureType();
                    string internationalNumber1 = "+94" + number.substring(1);
                    error? response = notification:sendsms(internationalNumber1, message);
                    io:print(response);

                    string fcm = passengerDoc["fcm"].toString();
                    string|error notifires = notification:sendFCMNotification(fcm, "Ride started", message, "carpooling-c6aa5");
                    io:print(notifires);
                    string currentTime = time:utcNow().toString();
                    map<json> notifyData = {
                        "user": PID,
                        "title": "Ride Start",
                        "massage": message,
                        "isread": false,
                        "createdAt": currentTime
                    };
                    json|error createResult = firebase:createFirestoreDocument(
                            "carpooling-c6aa5",
                            accessToken,
                            "notification",
                            notifyData
                    );
                    io:print(createResult);
                }
            }
        }
    }
    json successResponse = {
        "message": "Ride start successfully",
        "rideId": rideId,
        "status": "start"
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    return response;

}

public function endride(http:Request req) returns http:Response|error {
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    string rideId = check payload.rideId;
    io:print(rideId);
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }

     map<json> queryFilter = {"rideId": rideId};
    // First, get the specific ride document
    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    if rideDoc is error {
        return utility:createErrorResponse(500, "Failed to fetch ride document");
    }

    if rideDoc.length() == 0 {
        return utility:createErrorResponse(404, "Ride not found");
    }

    string actualDocumentId = <string>rideDoc[0]["id"];

    map<json> updateData = {
        "status": "completed"
    };
    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            actualDocumentId,
            updateData
        );

    if updateResult is error {
        return utility:createErrorResponse(500, "Failed to start ride");
    }
    string message = string `Your booked ride is completed successfully. see you again`;
    json passengersJson = rideDoc[0]["passengers"];
    if (passengersJson is json[]) {
        json[] passengers = <json[]>passengersJson;
        foreach int i in 0 ..< passengers.length() {
            json passenger = passengers[i];
            if passenger is map<json> {
                if passenger.hasKey("passengerId") {
                    string PID = check passenger["passengerId"].ensureType();
                    map<json>|error passengerDoc = firebase:getFirestoreDocumentById(
                            "carpooling-c6aa5",
                            accessToken,
                            "users",
                            PID
                        );
                    if (passengerDoc is error) {
                        break;
                    }

                    

                    string fcm = passengerDoc["fcm"].toString();
                    string|error notifires = notification:sendFCMNotification(fcm, "Ride started", message, "carpooling-c6aa5");
                    io:print(notifires);
                    string currentTime = time:utcNow().toString();
                    map<json> notifyData = {
                        "user": PID,
                        "title": "Ride Start",
                        "massage": message,
                        "isread": false,
                        "createdAt": currentTime
                    };
                    json|error createResult = firebase:createFirestoreDocument(
                            "carpooling-c6aa5",
                            accessToken,
                            "notification",
                            notifyData
                    );
                    io:print(createResult);
                }
            }
        }
    }
    json successResponse = {
        "message": "Ride end successfully",
        "rideId": rideId,
        "status": "start"
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    return response;

}