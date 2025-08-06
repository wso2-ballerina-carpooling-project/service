import 'service.Map;
import 'service.auth;
import 'service.call;
import 'service.firebase;
import 'service.notification;
import 'service.profile_management;
import 'service.report;
import 'service.ride_management;
import 'service.ride_management as ride_management1;
import 'service.utility;
import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import 'service.passenger_management;
import 'service.pwreset;
import 'service.ride_admin_management as rideAdmin;
import 'service.reports_management as reports;
import 'service.driver_management as drivers;
import ballerina/log;
import 'service.admin;
import 'service.user_report_management as userReports;

 // From your Config.toml

type Payment record {
    string id;
    boolean isPaid;
    string createdAt;
    string ride;
    string user;
    string amount;
};

type PaymentStats record {
    string month;
    int completedCount;
    int pendingCount;
    decimal completedPercentage;
    decimal pendingPercentage;
};





// 1. Define the CORS configuration with the CORRECT port number.
http:CorsConfig corsConfig = {
    allowOrigins: ["http://localhost:3000"], // <-- THE FIX IS HERE
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"]
};

// 2. Apply the CORS configuration using the @http:ServiceConfig annotation.
@http:ServiceConfig {
    cors: corsConfig
}
service /api on new http:Listener(9090) {

    // --- All your resource functions go here ---

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
    resource function post adminlogin(@http:Payload json payload) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = auth:adminlogin(payload, accessToken);
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

    resource function post changeroletopassenger(http:Request req)  returns http:Response|error{
        return profile_management:changeroletopassenger(req);
    }

    resource function post changeroletodriver(http:Request req) returns http:Response|error {
        return profile_management:changeroletodriver(req);
    }

    resource function post forgot(http:Request req) returns http:Response|error {
        return pwreset:forgotPassword(req);
    }
    resource function post resetpassword(http:Request req) returns http:Response|error {
        return pwreset:resetPassword(req);
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

    resource function get notifications(http:Request req) returns http:Response|error {
        string|error authHeader = req.getHeader("Authorization");
        if authHeader is error {
            return utility:createErrorResponse(404, "NotFound");
        }

        string jwtToken = authHeader.substring(7);

        jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
        if tokenPayload is error {
            return utility:createErrorResponse(404, "NotFound");
        }
        string|error accessToken = firebase:generateAccessToken();
        if accessToken is error {
            return utility:createErrorResponse(404, "NotFound");
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
        return utility:createSuccessResponse(200, {queryResult});
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

    resource function post rides/begin(http:Request req) returns http:Response|error {
        return ride_management:startride(req);
    }

    resource function post rides/end(http:Request req) returns http:Response|error {
        return ride_management:endride(req);
    }

    resource function post ride/cancel(http:Request req) returns http:Response|error {
        return ride_management:cancelDriverRide(req);
    }

    resource function get passengerOngoingRide(http:Request req) returns http:Response|error {
        return ride_management:getPassengerOngoing(req);
    }

    resource function get passengerCancelRide(http:Request req) returns http:Response|error {
        return ride_management:getPassengerCancel(req);
    }

    resource function get passengerCompleteRide(http:Request req) returns http:Response|error {
        return ride_management:getPassengerComplete(req);
    }

    resource function post cancelBooking(http:Request req) returns http:Response|error {
        return ride_management:cancelPassengerBooking(req);
    }

    //call
    resource function post generateToken(http:Request req) returns http:Response|error {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return utility:createErrorResponse(400, "Invalid JSON payload");
        }

        json channelNameJson = check payload.channelName;
        string channelName = channelNameJson.toString();
        json uidJson = check payload.uid;
        string uid = uidJson.toString();
        string token = check call:generateAgoraToken(
                channelName,
                uid,
                "32f8dd6fbfad4a18986c278345678b41",
                "ed981005f043484cbb82b80105f9e581"
        );
        return utility:createSuccessResponse(200, token);
    }

    resource function post call(http:Request req) returns http:Response|error {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return utility:createErrorResponse(400, "Invalid JSON payload");
        }
        json channelNameJson = check payload.channelName;
        string channelName = channelNameJson.toString();
        json passengerIDJson = check payload.passengerId;
        string passengerId = passengerIDJson.toString();
        io:print(passengerId);
        json callIdJson = check payload.callId;
        string callId = callIdJson.toString();
        json callerNameJson = check payload.callerName;
        string callerName = callerNameJson.toString();
        map<string> data = {
            "callId": callId,
            "channelName": channelName,
            "callerName": callerName
        };
        string|error notificationResult = notification:sendFCMNotification(
                passengerId,
                "Incoming Call",
                "Calling",
                "carpooling-c6aa5", // Your Firebase project ID
                data
        );

        if notificationResult is error {
            return utility:createErrorResponse(500, notificationResult.message());
        }
        return utility:createSuccessResponse(200, {"message": "Call notification sent successfully"});
    }

    //Report

    resource function post earnings(http:Request req) returns http:Response|error {
        json|error payload = req.getJsonPayload();
        if payload is error {
            return utility:createErrorResponse(400, "Invalid JSON payload");
        }
        string userId = check payload.userId;
        http:Response|report:ErrorResponse result = report:getUserEarnings(userId);
        if result is report:ErrorResponse {
            return utility:createErrorResponse(400, "Server error");
        }
        return result;
  
    }


    resource function get rides/admin(http:Request req) returns http:Response|error {
        // Manually and safely extract query parameters from the request URL
        map<string|string[]> queryParams = req.getQueryParams();

        // --- CORRECTED YEAR PARAMETER LOGIC ---

        if !queryParams.hasKey("year") {
            return utility:createErrorResponse(400, "Missing required query parameter: year");
        }
        
        string|string[] yearParam = queryParams.get("year");
        string yearString;

        // Use a type guard to handle both single string and array cases
        if yearParam is string[] {
            // If it's an array, take the first element
            yearString = yearParam[0];
        } else {
            // If it's a single string, just use it
            yearString = yearParam;
        }

        // Add a log to see exactly what we are trying to parse
        log:printInfo("Attempting to parse year: '" + yearString + "'");
        
        int|error year = int:fromString(yearString);
        if year is error {
            return utility:createErrorResponse(400, "Invalid value for query parameter 'year'. Must be an integer.");
        }

        // --- CORRECTED MONTH PARAMETER LOGIC ---
        
        if !queryParams.hasKey("month") {
            return utility:createErrorResponse(400, "Missing required query parameter: month");
        }

        string|string[] monthParam = queryParams.get("month");
        string monthString;

        if monthParam is string[] {
            monthString = monthParam[0];
        } else {
            monthString = monthParam;
        }

        // Add a log to see exactly what we are trying to parse
        log:printInfo("Attempting to parse month: '" + monthString + "'");
        
        int|error month = int:fromString(monthString);
        if month is error {
            return utility:createErrorResponse(400, "Invalid value for query parameter 'month'. Must be an integer.");
        }

        // Call the logic function with the validated parameters
        return rideAdmin:getRideStats(year, month);
    }
    # POST /api/reports/rides
    # Generates a downloadable CSV report.
   resource function post reports/rides(@http:Payload json payload) returns http:Response|error {
        int year = check payload.year.ensureType();
        int month = check payload.month.ensureType();
        return reports:generateRideReport(year, month);

    }
          // --- THIS IS THE NEW, CORRECTLY PLACED ENDPOINT ---
    # GET /api/rides/myreport
    # Gets a JSON report of all rides for the authenticated user.
    resource function get rides/myreport(http:Request req) returns http:Response|error {
        return userReports:getUserRideReport(req);
    }


    resource function get drivers() returns http:Response|error {
        return drivers:getDrivers();
    }

    resource function post drivers/approve(@http:Payload json payload) returns http:Response|error {
        return drivers:updateDriverStatus(payload, "approved");
    }


    resource function post drivers/reject(@http:Payload json payload) returns http:Response|error {
        return drivers:updateDriverStatus(payload, "rejected");
    }

    resource function get passengers() returns http:Response|error {
        return passenger_management:getPassengers();

    }

    resource function post passengers/approve(@http:Payload json payload) returns http:Response|error {
       return passenger_management:updatePassengerStatus(payload, "approved");
    }

    resource function post passengers/reject(@http:Payload json payload) returns http:Response|error {
       return passenger_management:updatePassengerStatus(payload, "rejected");
    }

    resource function get rides() returns http:Response|error{
        return admin:rides();
    }
    resource function get users() returns http:Response|error{
        return admin:users();
    }
    resource function get payments() returns http:Response|error{
        return admin:payments();
    }



}