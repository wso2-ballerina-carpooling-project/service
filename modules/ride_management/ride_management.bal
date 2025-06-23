import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerina/io;
import ballerina/jwt;

import 'service.firebase as firebase;
import 'service.utility as utility;

configurable string publicKey = ?;

// Define ride data types
type RideData record {
    string pickupLocation;
    string dropoffLocation;
    string date;
    string startTime;
    string returnTime;
    string vehicleRegNo;
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

// Post a ride function

public function verifyToken(string jwtToken) returns jwt:Payload|error {
    // Check if token is empty or null
    if jwtToken.trim() == "" {
        return error("JWT token is empty or null");
    }

    // JWT validator configuration
    jwt:ValidatorConfig validatorConfig = {
        issuer: "CarPool",
        audience: "CarPool-App",
        signatureConfig: {
            certFile: publicKey
        }
    };

    // Validate the JWT token
    jwt:Payload|error payload = jwt:validate(jwtToken, validatorConfig);
    
    if payload is error {
        log:printError("JWT validation failed", payload);
        return error("Invalid or expired token");
    }

    // Additional validation checks
    jwt:Payload validPayload = payload;
    
    // Check if token has expired manually (additional safety check)
    if validPayload.exp is int {
        int currentTime = time:utcNow()[0];
        if currentTime > validPayload.exp {
            return error("Token has expired");
        }
    }

    // Validate issuer and audience
    if validPayload.iss != "CarPool" {
        return error("Invalid token issuer");
    }

    if validPayload.aud != "CarPool-App" {
        return error("Invalid token audience");
    }

    return validPayload;
}
public function postARide(@http:Payload json payload, string accessToken, http:Request req) returns http:Response {
    io:print("Received ride payload: ", payload);
    
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
    
    // Extract user info from token
    // map<json> customClaims = check <map<json>>tokenPayload["customClaims"];
    string userId = <string>tokenPayload["id"];
    string userRole = <string>tokenPayload["role"];
    string userStatus = <string>tokenPayload["status"];
    
    // // Check if user is approved (except admin)
    if userRole != "admin" && userStatus != "approved" {
        return utility:createErrorResponse(403, "Your account is not approved to post rides");
    }
    
    // Validate ride data
    RideData|error rideData = payload.cloneWithType(RideData);
    if rideData is error {
        log:printError("Invalid ride data format", rideData);
        return utility:createErrorResponse(400, "Invalid ride data format");
    }
    
    // Validate required fields
    if rideData.pickupLocation == "" || rideData.dropoffLocation == "" || 
       rideData.date == "" || rideData.startTime == "" {
        return utility:createErrorResponse(400, "Missing required ride information");
    }
    
    // For drivers, they can specify their vehicle registration number
    // if userRole == "driver" && rideData.vehicleRegNo != "" {
    //     // Verify the vehicle belongs to the driver
    //     boolean|error vehicleValid = validateDriverVehicle(userId, rideData.vehicleRegNo, accessToken);
    //     if vehicleValid is error || !vehicleValid {
    //         return utility:createErrorResponse(400, "Invalid vehicle registration number for this driver");
    //     }
    // }
    
    // Create ride document
    string rideId = uuid:createType1AsString();
    string currentTime = time:utcNow().toString();
    
    map<json> rideDocument = {
        "rideId": rideId,
        "driverId": userId,
        "driverRole": userRole,
        "pickupLocation": rideData.pickupLocation,
        "dropoffLocation": rideData.dropoffLocation,
        "date": rideData.date,
        "startTime": rideData.startTime,
        "returnTime": rideData.returnTime,
        "vehicleRegNo": rideData.vehicleRegNo,
        "route": {
            "index": rideData.route.index,
            "duration": rideData.route.duration,
            "distance": rideData.route.distance,
            "polyline": rideData.route.polyline.toJson()
        },
        "status": "active",
        "createdAt": currentTime,
        "updatedAt": currentTime,
        "passengers": [] // Array to store passenger bookings
        // "maxPassengers": userRole == "driver" ? getDriverSeatingCapacity(userId, accessToken) : 1
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
    
    if queryResult is error {
       // log:printError("Failed to fetch user rides", queryResult);
        return utility:createErrorResponse(500, "Failed to fetch your rides");
    }
    
    return utility:createSuccessResponse(200, {
        "rides": queryResult,
        "count": queryResult.length()
    });
}

// Book a ride
// public function bookRide(string rideId, @http:Payload json payload, string accessToken, http:Request req) returns http:Response|error {
//     // Get authorization header
//     string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
//     if authHeader is http:HeaderNotFoundError {
//         return utility:createErrorResponse(401, "Authorization header missing");
//     }
    
//     // Extract and verify JWT token
//     string jwtToken = authHeader.substring(7);
//     jwt:Payload|error tokenPayload = verifyToken(jwtToken);
//     if tokenPayload is error {
//         return utility:createErrorResponse(401, "Invalid or expired token");
//     }
    
//     // Extract user info from token
//     map<json> customClaims = <map<json>>tokenPayload["customClaims"];
//     string userId = <string>customClaims["id"];
//     string userRole = <string>customClaims["role"];
//     string userStatus = <string>customClaims["status"];
    
//     // Check if user is approved
//     if userRole != "admin" && userStatus != "approved" {
//         return utility:createErrorResponse(403, "Your account is not approved to book rides");
//     }
    
//     // Get ride details first
//     map<json> rideFilter = {"rideId": rideId, "status": "active"};
//     map<json>[]|error rideQuery = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         accessToken,
//         "rides",
//         rideFilter
//     );
    
//     if rideQuery is error || rideQuery.length() == 0 {
//         return utility:createErrorResponse(404, "Ride not found or not available");
//     }
    
//     map<json> ride = rideQuery[0];
//     string driverId = <string>ride["driverId"];
    
//     // Check if user is trying to book their own ride
//     if driverId == userId {
//         return utility:createErrorResponse(400, "You cannot book your own ride");
//     }
    
//     // Check if user already booked this ride
//     json[] passengers = <json[]>ride["passengers"];
//     foreach json passenger in passengers {
//         map<json> passengerMap = <map<json>>passenger;
//         if <string>passengerMap["passengerId"] == userId {
//             return utility:createErrorResponse(400, "You have already booked this ride");
//         }
//     }
    
//     // Check ride capacity
//     int maxPassengers = <int>ride["maxPassengers"];
//     if passengers.length() >= maxPassengers {
//         return utility:createErrorResponse(400, "Ride is fully booked");
//     }
    
//     // Create booking
//     string bookingId = uuid:createType1AsString();
//     string currentTime = time:utcNow().toString();
    
//     map<json> booking = {
//         "bookingId": bookingId,
//         "passengerId": userId,
//         "passengerName": <string>customClaims["firstName"] + " " + <string>customClaims["lastName"],
//         "passengerPhone": <string>customClaims["phone"],
//         "bookedAt": currentTime,
//         "status": "confirmed"
//     };
    
//     // Add booking to passengers array
//     passengers.push(booking);
    
//     // Update ride document
//     map<json> updateData = {
//         "passengers": passengers,
//         "updatedAt": currentTime
//     };
    
//     // Update ride in Firestore (you'll need to implement updateFirestoreDocument in your firebase module)
//     json|error updateResult = firebase:updateFirestoreDocument(
//         "carpooling-c6aa5",
//         accessToken,
//         "rides",
//         rideId,
//         updateData
//     );
    
//     if updateResult is error {
//         log:printError("Failed to book ride", updateResult);
//         return utility:createErrorResponse(500, "Failed to book ride");
//     }
    
//     return utility:createSuccessResponse(200, {
//         "message": "Ride booked successfully",
//         "bookingId": bookingId,
//         "rideId": rideId
//     });
// }

// // Helper function to validate driver's vehicle
// function validateDriverVehicle(string userId, string vehicleRegNo, string accessToken) returns boolean|error {
//     map<json> userFilter = {"id": userId};
//     map<json>[]|error userQuery = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         accessToken,
//         "users",
//         userFilter
//     );
    
//     if userQuery is error || userQuery.length() == 0 {
//         return false;
//     }
    
//     map<json> user = userQuery[0];
//     json? driverDetails = user["driverDetails"];
    
//     if driverDetails is map<json> {
//         string? userVehicleRegNo = <string?>driverDetails["vehicleRegistrationNumber"];
//         return userVehicleRegNo == vehicleRegNo;
//     }
    
//     return false;
// }

// // Helper function to get driver's seating capacity
// function getDriverSeatingCapacity(string userId, string accessToken) returns int {
//     map<json> userFilter = {"id": userId};
//     map<json>[]|error userQuery = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         accessToken,
//         "users",
//         userFilter
//     );
    
//     if userQuery is error || userQuery.length() == 0 {
//         return 1; // Default capacity
//     }
    
//     map<json> user = userQuery[0];
//     json? driverDetails = user["driverDetails"];
    
//     if driverDetails is map<json> {
//         int? capacity = <int?>driverDetails["seatingCapacity"];
//         return capacity ?: 1;
//     }
    
//     return 1;
// }