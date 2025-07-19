import 'service.Map;
import 'service.auth;
import 'service.firebase;
import 'service.profile_management;
import 'service.ride_management;
import 'service.ride_management as ride_management1;
import 'service.utility;

import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import 'service.call;

service /api on new http:Listener(9090) {

    // resource function post call(@http:Payload json payload) {
    //     string phone = checkpanic payload.phone.ensureType();
    //     string validPhone = call:formatSriLankanPhoneNumber(phone);
    //     json|error result = call:executeFlow(validPhone, "+16205319231");
    //     if result is json {
    //         io:println("Flow execution successful:");
    //         io:println(result.toString());
    //     } else {
    //         // Handle error
    //         io:println("Error executing flow: ", result.message());
    //     }
    // }

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

    resource function post fcm(@http:Payload json payload) {
        string accessToken = checkpanic firebase:generateAccessToken();
        string? fcm = checkpanic payload.FCM.ensureType();
        string id = checkpanic payload.userId.ensureType();
        map<json> updateData = {
            "fcm": fcm
        };
        json|error updateResult = firebase:mergeFirestoreDocument(
                "carpooling-c6aa5",
                accessToken,
                "users",
                id,
                updateData
        );
        io:print(updateResult);

    }

    resource function post editName(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = profile_management:updateName(payload, req, accessToken);
        return response;
    }

    resource function post editPhone(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = profile_management:updatePhone(payload, req, accessToken);
        return response;
    }

    resource function post updateVehicle(@http:Payload json payload, http:Request req) returns http:Response|error {
        http:Response|error response = profile_management:updateVehicle(req);
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

    resource function post getStartRide(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        return ride_management:getStartRide(accessToken, req);
    }

    resource function post search(http:Request req) returns http:Response|error {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return utility:createErrorResponse(400, "Invalid JSON payload");
        }

        // Extract search parameters from JSON payload

        json dateJson = check payload.date;
        boolean isWayToWork = check payload.waytowork;

        // Get access token from environment or configuration
        string accessToken = checkpanic firebase:generateAccessToken();

        http:Response|error result = ride_management1:findMatchingRides(
                accessToken,
                req,
                dateJson,
                isWayToWork
        );

        return result;
    }

    resource function post rides/book(http:Request req) returns http:Response|error {
        http:Response|error result = ride_management:book(req);
        return result;
    }

    resource function post driverRideInfor(http:Request req) returns http:Response|error {
        http:Response|error result = ride_management:getCompleteRide(req);
        return result;
    }

    resource function get ongoingDriverRide(http:Request req) returns http:Response|error {
        http:Response|error result = ride_management:getOngoingRide(req);
        return result;
    }

    resource function get cancelDriverRide(http:Request req) returns http:Response|error {
        http:Response|error result = ride_management:getCancelRide(req);
        return result;
    }

    resource function post direction(http:Request req) returns http:Response|error {
        return Map:getDirection(req);
    }

    resource function post searchLocation(@http:Payload json payload) returns http:Response|error {
        string searchQuery = check payload.text.ensureType();
        io:println("Searching for places matching: '" + searchQuery + "'");
        http:Response|error results = Map:searchSriLankaPlaces(searchQuery);
        return results;
    }

    resource function get notifications(http:Request req) returns http:Response|error{
        string|error authHeader = req.getHeader("Authorization");
        if authHeader is error {
            return utility:createErrorResponse(404,"NotFound");
        }

        string jwtToken = authHeader.substring(7);

        jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
        if tokenPayload is error {
            return utility:createErrorResponse(404,"NotFound");
        }
        string|error accessToken = firebase:generateAccessToken();
        if accessToken is error {
            return utility:createErrorResponse(404,"NotFound");
        }
        string userId = <string>tokenPayload["id"];
        map<json> queryFilter = {"user": userId};
        map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
                "carpooling-c6aa5",
                accessToken,
                "notification",
                queryFilter
            );
        if queryResult is error {
            return utility:createErrorResponse(500, "Failed to book ride");
        }
        return utility:createSuccessResponse(200,{queryResult});
    }

    resource function get driver/[string driverId](http:Request request) returns http:Response|error {
        string|error accessToken = firebase:generateAccessToken();
        if accessToken is error {
            return utility:createErrorResponse(500, "Authentication failed");
        }
        json|error user = firebase:getFirestoreDocumentById(
                "carpooling-c6aa5",
                accessToken,
                "users",
                driverId
        );
        if user is error {
            // log:printError("Failed to fetch user rides", queryResult);
            return utility:createErrorResponse(500, "No completed rides");
        }
        io:print(user);
        return utility:createSuccessResponse(200, {"User": user});

    }

    resource function get passenger/[string passengerId](http:Request request) returns http:Response|error {
        string|error accessToken = firebase:generateAccessToken();
        if accessToken is error {
            return utility:createErrorResponse(500, "Authentication failed");
        }
        json|error user = firebase:getFirestoreDocumentById(
                "carpooling-c6aa5",
                accessToken,
                "users",
                passengerId
        );
        if user is error {
            // log:printError("Failed to fetch user rides", queryResult);
            return utility:createErrorResponse(500, "No completed rides");
        }
        io:print(user);
        return utility:createSuccessResponse(200, {"User": user});

    }

    resource function post rides/calculateCost(http:Request req) returns http:Response|error {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return utility:createErrorResponse(400, "Invalid JSON payload");
        }

        float distance = check payload.distance;
        io:print(distance);

        return utility:createSuccessResponse(200, {"cost": distance * 89});
    }

    resource function post ride/cancel(http:Request req) returns http:Response|error {
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

    resource function get passengerOngoingRide(http:Request req)returns http:Response|error  {
        return ride_management:getPassengerOngoing(req);
    }
    resource function get passengerCancelRide(http:Request req)returns http:Response|error  {
        return ride_management:getPassengerCancel(req);
    }
    resource function get passengerCompleteRide(http:Request req)returns http:Response|error  {
        return ride_management:getPassengerComplete(req);
    }
    resource function post cancelBooking(http:Request req)returns http:Response|error  {
        return ride_management:cancelPassengerBooking(req);
    }

    resource function post initiateCall(http:Request req) returns  http:Response|error {
        return call:call(req);
    }

}

