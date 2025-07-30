import ballerina/http;
import 'service.firebase as firebase;
import ballerina/log;
import ballerina/time;
// NOTE: The import for lang.string has been removed as we are no longer using it.

// This is the main function for generating the CSV report.
// This is the main function for generating the CSV report.
public function generateRideReport(int year, int month) returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();

    // --- WORKAROUND LOGIC STARTS HERE ---
    // We will query for each status type individually because queryFirestoreDocuments
    // in the firebase.bal module cannot handle an empty filter.
    map<json>[] allRides = [];

    // Query 1: Get all "active" rides
    map<json>[]|error activeRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "active"});
    if activeRides is map<json>[] {
        allRides.push(...activeRides);
    } else {
        log:printWarn("Could not retrieve active rides for report", activeRides);
    }

    // Query 2: Get all "start" rides
    map<json>[]|error startRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "start"});
    if startRides is map<json>[] {
        allRides.push(...startRides);
    } else {
        log:printWarn("Could not retrieve ongoing rides for report", startRides);
    }

    // Query 3: Get all "completed" rides
    map<json>[]|error completedRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "completed"});
    if completedRides is map<json>[] {
        allRides.push(...completedRides);
    } else {
        log:printWarn("Could not retrieve completed rides for report", completedRides);
    }

    // Query 4: Get all "cancel" rides
    map<json>[]|error cancelledRidesData = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "cancel"});
    if cancelledRidesData is map<json>[] {
        allRides.push(...cancelledRidesData);
    } else {
        log:printWarn("Could not retrieve cancelled rides for report", cancelledRidesData);
    }
    // --- WORKAROUND LOGIC ENDS HERE ---


    // Step 2: Filter rides for the selected month and year
    map<json>[] filteredRides = from var ride in allRides
        where isRideInMonth(ride, year, month)
        select ride;
    
    // Step 3: Enrich the data by fetching user names
    map<json>[] enrichedRides = [];
    map<string> userCache = {};
    foreach var ride in filteredRides {
        enrichedRides.push(check enrichRideData(ride, accessToken, userCache));
    }

    // Step 4: Convert the enriched data into a CSV formatted string
    string csvString = check createCsvString(enrichedRides);

    // Step 5: Create a special HTTP response that triggers a file download
    http:Response response = new;
    response.statusCode = http:STATUS_OK;
    response.setTextPayload(csvString);
    response.setHeader("Content-Type", "text/csv");
    string fileName = string `ride_report_${year}_${month}.csv`;
    response.setHeader("Content-Disposition", string `attachment; filename="${fileName}"`);

    return response;
}

// Helper function to check if a ride occurred in the given month and year
function isRideInMonth(map<json> ride, int year, int month) returns boolean {
    if !(ride.hasKey("createdAt") && ride.createdAt is string) {
        return false;
    }
    time:Utc|error rideTime = time:utcFromString(checkpanic ride.createdAt.ensureType());
    if rideTime is error {
        log:printWarn("Could not parse createdAt timestamp for a ride", rideTime);
        return false;
    }
    time:Civil civilTime = time:utcToCivil(rideTime);
    return civilTime.year == year && civilTime.month == month;
}

// Helper function to fetch driver and passenger names for the report
function enrichRideData(map<json> ride, string accessToken, map<string> userCache) returns map<json>|error {
    map<json> enriched = ride.clone();

    string driverId = checkpanic ride.driverId.ensureType();
    enriched["driverName"] = check getUserName(driverId, accessToken, userCache);

    string[] passengerNames = [];
    if ride.hasKey("passengers") && ride.passengers is json[] {
        json[] passengersArray = checkpanic ride.passengers.ensureType();
        foreach var p in passengersArray {
            if p is map<json> && p.hasKey("passengerId") {
                string passengerId = checkpanic p.passengerId.ensureType();
                passengerNames.push(check getUserName(passengerId, accessToken, userCache));
            }
        }
    }
    enriched["passengerNames"] = passengerNames;
    return enriched;
}

// Helper function to get a user's name, with caching for improved performance
function getUserName(string userId, string accessToken, map<string> userCache) returns string|error {
    string? cachedName = userCache[userId];
    if cachedName is string {
        return cachedName;
    }

    map<json>|error userData = firebase:getFirestoreDocumentById("carpooling-c6aa5", accessToken, "users", userId);
    if userData is map<json> && userData.hasKey("name") {
        string name = checkpanic userData.name.ensureType();
        userCache[userId] = name;
        return name;
    }
    return "Unknown User";
}

// THIS IS THE FULLY REWRITTEN AND CORRECTED FUNCTION
// It no longer uses the complex 'strings:join' function.
function createCsvString(map<json>[] data) returns string|error {
    string[] csvRows = [];
    // Define the header row for the CSV file
    csvRows.push("Ride ID,Date,Driver Name,Passenger Names,Status");

    foreach var ride in data {
        string rideId = ride.hasKey("rideId") ? checkpanic ride.rideId.ensureType() : "N/A";
        string date = ride.hasKey("date") ? checkpanic ride.date.ensureType() : "N/A";
        string driverName = checkpanic ride.driverName.ensureType();
        string status = ride.hasKey("status") ? checkpanic ride.status.ensureType() : "N/A";
        
        string[] passengerNamesArray = checkpanic ride.passengerNames.ensureType();
        
        // --- MANUAL STRING JOIN LOGIC (START) ---
        string passengersString = "";
        if passengerNamesArray.length() > 0 {
            // Manually build the comma-separated string
            passengersString = passengerNamesArray[0];
            foreach int i in 1 ..< passengerNamesArray.length() {
                passengersString = passengersString + ", " + passengerNamesArray[i];
            }
        }
        // --- MANUAL STRING JOIN LOGIC (END) ---

        // Construct the CSV row using a template string
        csvRows.push(string `"${rideId}","${date}","${driverName}","${passengersString}","${status}"`);
    }

    // --- MANUAL STRING JOIN LOGIC FOR FINAL CSV (START) ---
    string finalCsv = "";
    if csvRows.length() > 0 {
        finalCsv = csvRows[0];
        foreach int i in 1 ..< csvRows.length() {
            finalCsv = finalCsv + "\n" + csvRows[i];
        }
    }
    // --- MANUAL STRING JOIN LOGIC FOR FINAL CSV (END) ---
    
    return finalCsv;
}