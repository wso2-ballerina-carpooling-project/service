import ballerina/http;
import 'service.firebase as firebase;
import 'service.utility as utility;
import ballerina/log;
import ballerina/time;

// This function gets all rides and calculates stats for a given month and year.
// This function gets all rides and calculates stats for a given month and year.
// This function gets all rides and calculates stats for a given month and year.
public function getRideStats(int year, int month) returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();

    // --- WORKAROUND LOGIC STARTS HERE ---
    // We will query for each status type individually because queryFirestoreDocuments
    // in the firebase.bal module cannot handle an empty filter.
    map<json>[] allRides = [];

    // Query 1: Get all "active" (Scheduled) rides
    map<json>[]|error activeRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "active"});
    if activeRides is map<json>[] {
        allRides.push(...activeRides);
    } else {
        log:printWarn("Could not retrieve active rides", activeRides);
    }

    // Query 2: Get all "start" (Ongoing) rides
    map<json>[]|error startRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "start"});
    if startRides is map<json>[] {
        allRides.push(...startRides);
    } else {
        log:printWarn("Could not retrieve ongoing rides", startRides);
    }

    // Query 3: Get all "completed" rides
    map<json>[]|error completedRides = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "rides", {"status": "completed"});
    if completedRides is map<json>[] {
        allRides.push(...completedRides);
    } else {
        log:printWarn("Could not retrieve completed rides", completedRides);
    }

    // Query 4: Get all "cancel" (Cancelled) rides
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
        if !(ride.hasKey("createdAt") && ride.createdAt is string) {
            continue;
        }
        time:Utc|error rideTime = time:utcFromString(checkpanic ride.createdAt.ensureType());
        if rideTime is error {
            log:printWarn("Could not parse createdAt timestamp for a ride", rideTime);
            continue;
        }
        
        time:Civil civilTime = time:utcToCivil(rideTime);

        if civilTime.year == year && civilTime.month == month {
            string status = ride.hasKey("status") ? checkpanic ride.status.ensureType() : "Scheduled";

            match status {
                "active" => { scheduledCount += 1; }
                "start"   => { ongoingCount += 1; }
                "completed" => { completedCount += 1; }
                "cancel"  => { cancelledCount += 1; }
            }
        }
    }

    map<json> responseData = {
        scheduledRides: scheduledCount,
        ongoingRides: ongoingCount,
        completedRides: completedCount,
        cancelledRides: cancelledCount
    };

    return utility:createSuccessResponse(200, responseData);
}