import ballerina/http;
import 'service.firebase as firebase;
import 'service.utility as utility;
import ballerina/log;

// This function gets all rides and calculates stats for a given month and year.
public function getRideStats(int year, int month) returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();

    // --- WORKAROUND LOGIC STARTS HERE ---
    map<json>[] allRides = [];

    map<json>[]|error activeRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "active"});
    if activeRides is map<json>[] {
        allRides.push(...activeRides);
    } else {
        log:printWarn("Could not retrieve active rides", activeRides);
    }

    map<json>[]|error startRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "start"});
    if startRides is map<json>[] {
        allRides.push(...startRides);
    } else {
        log:printWarn("Could not retrieve ongoing rides", startRides);
    }

    map<json>[]|error completedRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "completed"});
    if completedRides is map<json>[] {
        allRides.push(...completedRides);
    } else {
        log:printWarn("Could not retrieve completed rides", completedRides);
    }

    map<json>[]|error cancelledRidesData = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "cancel"});
    if cancelledRidesData is map<json>[] {
        allRides.push(...cancelledRidesData);
    } else {
        log:printWarn("Could not retrieve cancelled rides", cancelledRidesData);
    }
    // --- WORKAROUND LOGIC ENDS HERE ---

    int scheduledCount = 0;
    int ongoingCount = 0;
    int completedCount = 0;
    int cancelledCount = 0;

    foreach var ride in allRides {
        if !(ride.hasKey("date") && ride.date is string) {
            continue;
        }

        string dateString = checkpanic ride.date.ensureType();
        
        // --- FINAL FIX: Handle 'int?' return type from indexOf ---
        int? firstSlashIndex = dateString.indexOf("/");
        if firstSlashIndex is () { continue; } // Check for nil

        int? secondSlashIndex = dateString.indexOf("/", firstSlashIndex + 1);
        if secondSlashIndex is () { continue; } // Check for nil

        string monthString = dateString.substring(firstSlashIndex + 1, secondSlashIndex);
        string yearString = dateString.substring(secondSlashIndex + 1);
        // --- End of Final Fix ---
        
        int|error rideMonth = int:fromString(monthString);
        int|error rideYear = int:fromString(yearString);

        if rideMonth is error || rideYear is error {
            continue;
        }
        
        if rideYear == year && rideMonth == month {
            string status = ride.hasKey("status") ? checkpanic ride.status.ensureType() : "unknown";

            match status {
                "active" => { scheduledCount += 1; }
                "start"   => { ongoingCount += 1; }
                "completed" => { completedCount += 1; }
                "cancel"  => { cancelledCount += 1; }
            }
        }
    }

    map<json> responseData = {
        totalRides: scheduledCount + ongoingCount + completedCount + cancelledCount,
        ongoingRides: ongoingCount,
        completedRides: completedCount,
        cancelledRides: cancelledCount
    };

    return utility:createSuccessResponse(200, responseData);
}