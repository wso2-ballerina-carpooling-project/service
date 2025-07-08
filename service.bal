import 'service.Map;
import 'service.auth;
import 'service.firebase;
import 'service.ride_management;
import 'service.ride_management as ride_management1;
import 'service.utility;
import ballerina/http;
import ballerina/io;
import 'service.profile_management;


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

    resource function post editName(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = profile_management:updateName(payload,req,accessToken);
        return response;
    }
    resource function post editPhone(@http:Payload json payload, http:Request req) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = profile_management:updatePhone(payload,req,accessToken);
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
        http:Response|error result = ride_management:book(req);
        return result;
    }
    resource function post driverRideInfor(http:Request req) returns http:Response|error {
        http:Response|error result = ride_management:getDriverRideInfo(req);
        return result;
    }

    resource function post direction(http:Request req) returns http:Response|error{
        return Map:getDirection(req);
    }

    resource function post searchLocation(@http:Payload json payload) returns http:Response|error {
        string searchQuery = check payload.text.ensureType();
        io:println("Searching for places matching: '" + searchQuery + "'");
        http:Response|error results = Map:searchSriLankaPlaces(searchQuery);
        return results;
    }
}


