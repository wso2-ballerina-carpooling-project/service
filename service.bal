import 'service.Map;
import 'service.admin;
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
import 'service.call;
import 'service.notification;
import 'service.passenger_management;
import 'service.pwreset;
import 'service.ride_admin_management as rideAdmin;
import 'service.reports_management as reports;
import 'service.driver_management as drivers;
import ballerina/log;
import ballerina/time;

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




    // --- RIDES ADMIN & REPORTS ENDPOINTS ---

    # GET /api/rides/admin
    # Fetches ride statistics. Expects query parameters: ?year=2024&month=7
    
        # GET /api/rides/admin
    # Fetches ride statistics. Expects query parameters: ?year=2024&month=7
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


    // FIXED ADMIN ENDPOINTS - Simple GET requests without JSON payload
    // resource function get admin/bookedRides(http:Request req) returns http:Response|error {
    //     io:println("=== Calling admin/bookedRides endpoint ===");
    //     int|error bookedRides = admin:getBookedRidesWithinDay();
    //     if bookedRides is error {
    //         io:println("Error in getBookedRidesWithinDay: " + bookedRides.message());
    //         return utility:createErrorResponse(500, "Failed to get booked rides");
    //     }
    //     io:println("Booked rides count: " + bookedRides.toString());
    //     http:Response response = new;
    //     response.statusCode = 200;
    //     response.setJsonPayload({ "bookedRides": bookedRides });
    //     return response;
    // }

    resource function get admin/bookedRides(http:Request req) returns http:Response|error {
        io:println("=== Calling admin/bookedRides endpoint ===");
        int|error bookedRides = admin:getBookedRidesWithinDay(); // Assuming this is in the same module
        if bookedRides is error {
            io:println("Error in getBookedRidesWithinDay: " + bookedRides.message());
            return utility:createErrorResponse(500, "Failed to get booked rides");
        }
        io:println("Booked rides count: " + bookedRides.toString());
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({"bookedRides": bookedRides});
        return response;
    }

    resource function get admin/canceledRides(http:Request req) returns http:Response|error {
        io:println("=== Calling admin/canceledRides endpoint ===");
        int|error canceledRides = admin:getDriverCanceledRidesWithinDay();
        if canceledRides is error {
            io:println("Error in getDriverCanceledRidesWithinDay: " + canceledRides.message());
            return utility:createErrorResponse(500, "Failed to get canceled rides");
        }
        io:println("Canceled rides count: " + canceledRides.toString());
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({"canceledRides": canceledRides});
        return response;
    }

    // resource function get admin/pendingUsers(http:Request req) returns http:Response|error {
    //     io:println("=== Calling admin/pendingUsers endpoint ===");
    //     int|error pendingUsersCount = admin:getPendingUsersCount();
    //     if pendingUsersCount is error {
    //         io:println("Error in getPendingUsersCount: " + pendingUsersCount.message());
    //         return utility:createErrorResponse(500, "Failed to get pending users count");
    //     }
    //     io:println("Pending users count: " + pendingUsersCount.toString());
    //     http:Response response = new;
    //     response.statusCode = 200;
    //     response.setJsonPayload({"pendingUsers": pendingUsersCount});
    //     return response;
    // }

    resource function get admin/pendingUsers(http:Request req) returns http:Response|error {
        io:println("=== Calling admin/pendingUsers endpoint ===");
        int|error pendingUsersCount = admin:getPendingUsersCount();
        if pendingUsersCount is error {
            io:println("Error in getPendingUsersCount: " + pendingUsersCount.message());
            return utility:createErrorResponse(500, "Failed to get pending users count");
        }
        io:println("Pending users count: " + pendingUsersCount.toString());
        http:Response response = new;
        response.statusCode = 200;
        response.setJsonPayload({"pendingUsers": pendingUsersCount});
        return response;
    }



// Payment statistics endpoint

resource function get payments/statistics(http:Caller caller, http:Request req) returns error? {
    
    // Get query parameters for year and month filtering (optional)
    string? yearParam = req.getQueryParamValue("year");
    string? monthParam = req.getQueryParamValue("month");
    
    json response = {
        "success": false,
        "message": "",
        "data": []
    };

    do {
        json[] stats = [];
        
        // If specific year and month provided, get stats for that month
        if (yearParam is string && monthParam is string) {
            int year = check int:fromString(yearParam);
            int month = check int:fromString(monthParam);
            json monthStats = check getMonthlyPaymentStats(year, month);
            stats = [monthStats];
        } else if (yearParam is string) {
            // Get stats for entire year
            int year = check int:fromString(yearParam);
            stats = check getYearlyPaymentStats(year);
        } else {
            // Get stats for current year if no parameters provided
            time:Utc currentTime = time:utcNow();
            time:Civil civilTime = time:utcToCivil(currentTime);
            stats = check getYearlyPaymentStats(civilTime.year);
        }

        response = {
            "success": true,
            "message": "Payment statistics retrieved successfully",
            "data": stats
        };

    } on fail error e {
        io:println("Error retrieving payment statistics: " + e.message());
        response = {
            "success": false,
            "message": string `Error retrieving payment statistics: ${e.message()}`,
            "data": []
        };
    }

    http:Response httpResponse = new;
    httpResponse.setJsonPayload(response);
    httpResponse.setHeader("Content-Type", "application/json");
    
    error? result = caller->respond(httpResponse);
    if (result is error) {
        io:println("Error sending response: " + result.message());
    }
}

}

// Helper function to get payment statistics for a specific month
function getMonthlyPaymentStats(int year, int month) returns json|error {
    
    // TODO: Replace this section with your actual Firestore query
    // This is where you'll implement the Firestore logic to:
    // 1. Query payments collection
    // 2. Filter by date range
    // 3. Count documents where isPaid = true vs isPaid = false
    
    int completedCount = 0;
    int pendingCount = 0;
    int totalCount = 0;
    
    // PLACEHOLDER IMPLEMENTATION - Replace with actual Firestore code
    // Mock data for testing - replace with actual query results
    totalCount = 100;
    completedCount = 65;
    pendingCount = 35;
    
    // Calculate percentages
    float completedPercentage = totalCount > 0 ? (<float>completedCount / <float>totalCount) * 100.0 : 0.0;
    float pendingPercentage = totalCount > 0 ? (<float>pendingCount / <float>totalCount) * 100.0 : 0.0;
    
    // Get month name
    string monthName = getMonthName(month);
    
    return {
        "year": year,
        "month": month,
        "monthName": monthName,
        "completedCount": completedCount,
        "pendingCount": pendingCount,
        "totalCount": totalCount,
        "completedPercentage": completedPercentage,
        "pendingPercentage": pendingPercentage
    };
}

// Helper function to get payment statistics for entire year (all 12 months)
function getYearlyPaymentStats(int year) returns json[]|error {
    json[] yearlyStats = [];
    
    // Get stats for each month of the year
    foreach int month in 1...12 {
        json monthStats = check getMonthlyPaymentStats(year, month);
        yearlyStats.push(monthStats);
    }
    
    return yearlyStats;
}

// Helper function to get month name
function getMonthName(int month) returns string {
    match month {
        1 => { return "January"; }
        2 => { return "February"; }
        3 => { return "March"; }
        4 => { return "April"; }
        5 => { return "May"; }
        6 => { return "June"; }
        7 => { return "July"; }
        8 => { return "August"; }
        9 => { return "September"; }
        10 => { return "October"; }
        11 => { return "November"; }
        12 => { return "December"; }
        _ => { return "Unknown"; }
    }

    # POST /api/reports/rides
    # Generates a downloadable CSV report.
   resource function post reports/rides(@http:Payload json payload) returns http:Response|error {
        int year = check payload.year.ensureType();
        int month = check payload.month.ensureType();
        return reports:generateRideReport(year, month);

    }


    // --- DRIVER MANAGEMENT ENDPOINTS ---

# GET /api/drivers
# Fetches all users with the 'driver' role and processes their data for the frontend.
resource function get drivers() returns http:Response|error {
    return drivers:getDrivers();
}

# POST /api/drivers/approve
# Updates a specific driver's status to "approved".
resource function post drivers/approve(@http:Payload json payload) returns http:Response|error {
    return drivers:updateDriverStatus(payload, "approved");
}

# POST /api/drivers/reject
# Updates a specific driver's status to "rejected".
resource function post drivers/reject(@http:Payload json payload) returns http:Response|error {
    return drivers:updateDriverStatus(payload, "rejected");
}





    // --- PASSENGER MANAGEMENT ENDPOINTS ---

    # GET /api/passengers
    resource function get passengers() returns http:Response|error {
        return passenger_management:getPassengers();

    }

    # POST /api/passengers/approve
    resource function post passengers/approve(@http:Payload json payload) returns http:Response|error {
       return passenger_management:updatePassengerStatus(payload, "approved");
    }

    # POST /api/passengers/reject
    resource function post passengers/reject(@http:Payload json payload) returns http:Response|error {
       return passenger_management:updatePassengerStatus(payload, "rejected");
    }


}