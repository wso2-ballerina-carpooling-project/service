import ballerina/http;
import 'service.firebase as firebase;
import ballerina/log;
// The 'strings' import is no longer needed for the corrected function.

// This is the main function for generating the CSV report.
public function generateRideReport(int year, int month) returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();

    // --- WORKAROUND LOGIC ---
    map<json>[] allRides = [];
    map<json>[]|error activeRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "active"});
    if activeRides is map<json>[] { allRides.push(...activeRides); }
    map<json>[]|error startRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "start"});
    if startRides is map<json>[] { allRides.push(...startRides); }
    map<json>[]|error completedRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "completed"});
    if completedRides is map<json>[] { allRides.push(...completedRides); }
    map<json>[]|error cancelledRidesData = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "cancel"});
    if cancelledRidesData is map<json>[] { allRides.push(...cancelledRidesData); }
    // --- END WORKAROUND ---

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
    if !(ride.hasKey("date") && ride.date is string) {
        return false;
    }

    string dateString = checkpanic ride.date.ensureType();
    
    // Manual Date Parsing using indexOf and substring
    int? firstSlashIndex = dateString.indexOf("/");
    if firstSlashIndex is () { return false; }

    int? secondSlashIndex = dateString.indexOf("/", firstSlashIndex + 1);
    if secondSlashIndex is () { return false; }

    string monthString = dateString.substring(firstSlashIndex + 1, secondSlashIndex);
    string yearString = dateString.substring(secondSlashIndex + 1);
    
    int|error rideMonth = int:fromString(monthString);
    int|error rideYear = int:fromString(yearString);

    if rideMonth is error || rideYear is error {
        log:printWarn("Could not parse month or year from date string: " + dateString);
        return false;
    }

    return rideYear == year && rideMonth == month;
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

// --- THIS IS THE CORRECTED FUNCTION ---
// Helper function to get a user's name, with caching for improved performance
function getUserName(string userId, string accessToken, map<string> userCache) returns string|error {
    string? cachedName = userCache[userId];
    if cachedName is string {
        return cachedName;
    }

    map<json>|error userData = firebase:getFirestoreDocumentById("carpooling-c6aa5", accessToken, "users", userId);

    // Check if the document was found and has both firstName and lastName fields
    if userData is map<json> && userData.hasKey("firstName") && userData.hasKey("lastName") {
        // Safely extract first and last names
        string firstName = checkpanic userData.firstName.ensureType();
        string lastName = checkpanic userData.lastName.ensureType();

        // Combine them to create the full name
        string fullName = firstName + " " + lastName;

        // Cache the full name for future lookups
        userCache[userId] = fullName;
        return fullName;
    }
    
    // If anything fails (user not found, fields missing), return the default value
    return "Unknown User";
}


// This function creates the CSV string from the ride data.
function createCsvString(map<json>[] data) returns string|error {
    string[] csvRows = [];
    // Define the header row for the CSV file
    csvRows.push("Ride ID,Date,Driver Name,Passenger Names,Status");

    foreach var ride in data {
        string rideId = ride.hasKey("rideId") ? ride.get("rideId").toString() : "N/A";
        string date = ride.hasKey("date") ? ride.get("date").toString() : "N/A";
        string driverName = ride.hasKey("driverName") ? ride.get("driverName").toString() : "N/A";
        string status = ride.hasKey("status") ? ride.get("status").toString() : "N/A";
        
        string[] passengerNamesArray = [];
        // Safely extract the array of passenger names
        if ride.hasKey("passengerNames") {
             json passengerNamesJson = ride.get("passengerNames");
             if passengerNamesJson is string[] {
                 passengerNamesArray = passengerNamesJson;
             }
        }
        
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