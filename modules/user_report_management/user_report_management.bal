import ballerina/http;
import 'service.firebase as firebase;
import 'service.utility as utility;
import 'service.ride_management;
import ballerina/log;
import ballerina/jwt;

// Helper function to create a CSV string from ride data.
function createRideCsvString(map<json>[] rides, string headerTitle) returns string {
    if rides.length() == 0 {
        return ""; // Return empty string if no rides
    }
    
    string[] csvRows = [];
    csvRows.push(headerTitle); // e.g., "Rides as Driver"
    csvRows.push("Date,From,To,Status"); // Column headers

    foreach var ride in rides {
        string rideDate = ride.hasKey("date") ? ride.get("date").toString() : "N/A";
        string startLoc = ride.hasKey("startLocation") ? ride.get("startLocation").toString() : "N/A";
        string endLoc = ride.hasKey("endLocation") ? ride.get("endLocation").toString() : "N/A";
        string status = ride.hasKey("status") ? ride.get("status").toString() : "N/A";

        // Escape commas in location names by putting them in quotes
        csvRows.push(string `"${rideDate}","${startLoc}","${endLoc}","${status}"`);
    }

    // Join all rows with a newline character. Add extra space between sections.
    string finalCsv = "";
    if csvRows.length() > 0 {
        finalCsv = csvRows[0];
        foreach int i in 1 ..< csvRows.length() {
            finalCsv = finalCsv + "\n" + csvRows[i];
        }
    }
    return finalCsv + "\n\n";
}


// This is the main function, now updated to handle the 'format' query parameter.
public function getUserRideReport(http:Request req) returns http:Response|error {
    // 1. Authenticate the user (same as before)
    string|error authHeader = req.getHeader("Authorization");
    if authHeader is error {
        return utility:createErrorResponse(401, "Authorization header missing");
    }
    string jwtToken = authHeader.substring(7);
    jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
    if tokenPayload is error {
        return utility:createErrorResponse(401, "Invalid or expired token");
    }
    string userId = <string>tokenPayload["id"];
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Server authentication failed");
    }

    // 2. Fetch Driven Rides (same as before)
    map<json>[]|error drivenRidesResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"driverId": userId});
    map<json>[] drivenRides = [];
    if drivenRidesResult is map<json>[] {
        drivenRides.push(...drivenRidesResult);
    }

    // 3. Fetch Taken Rides (same as before)
    map<json>[] allRides = [];
    map<json>[]|error activeRidesResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "active"});
    if activeRidesResult is map<json>[] { allRides.push(...activeRidesResult); }
    map<json>[]|error startRidesResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "start"});
    if startRidesResult is map<json>[] { allRides.push(...startRidesResult); }
    map<json>[]|error completedRidesResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "completed"});
    if completedRidesResult is map<json>[] { allRides.push(...completedRidesResult); }
    map<json>[]|error cancelledRidesResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "cancel"});
    if cancelledRidesResult is map<json>[] { allRides.push(...cancelledRidesResult); }
    
    map<json>[] takenRides = [];
    foreach map<json> ride in allRides {
        if ride.hasKey("passengers") && ride.get("passengers") is json[] {
            json[] passengersArray = <json[]>ride.get("passengers");
            foreach var passenger in passengersArray {
                if passenger is map<json> && passenger.hasKey("passengerId") && passenger.get("passengerId") == userId {
                    takenRides.push(ride);
                    break;
                }
            }
        }
    }

    // --- START OF NEW LOGIC ---
    // 4. Check for the 'format' query parameter
    string? format = req.getQueryParamValue("format");

    if (format is string && format.toLowerAscii() == "csv") {
        // --- Generate and Return a CSV File ---
        string drivenRidesCsv = createRideCsvString(drivenRides, "Rides as Driver");
        string takenRidesCsv = createRideCsvString(takenRides, "Rides as Passenger");

        string finalCsvPayload = drivenRidesCsv + takenRidesCsv;

        http:Response response = new;
        response.statusCode = http:STATUS_OK;
        response.setTextPayload(finalCsvPayload);
        response.setHeader("Content-Type", "text/csv");
        response.setHeader("Content-Disposition", "attachment; filename=\"MyRideReport.csv\"");
        return response;

    } else {
        // --- Return JSON by default (for the mobile app) ---
        json reportPayload = {
            "drivenRides": drivenRides,
            "takenRides": takenRides
        };
        return utility:createSuccessResponse(200, reportPayload);
    }
    // --- END OF NEW LOGIC ---
}