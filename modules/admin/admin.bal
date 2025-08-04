import ballerina/io;
import ballerina/log;
import ballerina/time;
import ballerina/regex;
import 'service.firebase as firebase; 


public function getBookedRidesWithinDay() returns int|error {
    string|error firebaseAccessToken = firebase:generateAccessToken();
    if firebaseAccessToken is error {
        log:printError("Failed to generate access token", firebaseAccessToken);
        return error("Authentication failed");
    }

    // Get current time and calculate 24 hours ago
    int currentTime = time:utcNow()[0]; // Current time in seconds
    int twentyFourHoursAgo = currentTime - (24 * 60 * 60); // 24 hours in seconds

    // Define the query to filter rides directly in Firestore
    // CORRECTED: All keys are now strings (e.g., "structuredQuery")
    map<json> query = {
        "structuredQuery": {
            "from": [{
                "collectionId": "rides"
            }],
            "where": {
                "compositeFilter": {
                    "op": "AND",
                    "filters": [
                        {
                            "fieldFilter": {
                                "field": { "fieldPath": "status" },
                                "op": "EQUAL",
                                "value": { "stringValue": "active" }
                            }
                        },
                        {
                            "fieldFilter": {
                                "field": { "fieldPath": "updatedAt" },
                                "op": "GREATER_THAN_OR_EQUAL",
                                "value": { "integerValue": twentyFourHoursAgo }
                            }
                        }
                    ]
                }
            }
        }
    };

    // Query filtered rides from Firestore
    map<json>[]|error rideDocs = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        firebaseAccessToken,
        "rides",
        query
    );

    if rideDocs is error {
        log:printError("Failed to fetch rides", rideDocs);
        return error("Failed to fetch ride data");
    }

    int totalBookedRides = 0;
    foreach var ride in rideDocs {
        if ride.hasKey("passengers") {
            json passengersJson = ride["passengers"];
            if passengersJson is json[] {
                json[] passengers = <json[]>passengersJson;
                boolean hasConfirmedPassenger = false;
                foreach var passenger in passengers {
                    if passenger is map<json> && passenger.hasKey("status") {
                        string|error passengerStatus = passenger["status"].ensureType(string);
                        if passengerStatus is string && passengerStatus == "confirmed" {
                            hasConfirmedPassenger = true;
                            break;
                        }
                    }
                }
                if hasConfirmedPassenger {
                    totalBookedRides += 1;
                }
            }
        }
    }

    return totalBookedRides;
}


//cancelled rides
public function getDriverCanceledRidesWithinDay() returns int|error {
    string|error firebaseAccessToken = firebase:generateAccessToken();
    if firebaseAccessToken is error {
        log:printError("Failed to generate access token", firebaseAccessToken);
        return error("Authentication failed");
    }

    // Get current time and calculate 24 hours ago
    int currentTime = time:utcNow()[0]; // Current time in seconds
    int twentyFourHoursAgo = currentTime - (24 * 60 * 60); // 24 hours in seconds

    // Query rides with status "cancelled" from Firestore
    map<json> queryFilter = {"status": "cancelled"};
    map<json>[]|error rideDocs = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        firebaseAccessToken,
        "rides",
        queryFilter
    );

    if rideDocs is error {
        log:printError("Failed to fetch rides", rideDocs);
        return error("Failed to fetch ride data");
    }

    int totalCanceledRides = 0;
    foreach var ride in rideDocs {
        if ride.hasKey("updatedAt") {
            int|error updatedAt = ride["updatedAt"].ensureType(int);
            if updatedAt is int && updatedAt >= twentyFourHoursAgo {
                totalCanceledRides += 1;
            }
        }
    }

    return totalCanceledRides;
}

// new users
// public function getPendingUsersCount() returns int|error {
//     string|error accessToken = firebase:generateAccessToken();
//     if accessToken is error {
//         log:printError("Failed to generate access token", accessToken);
//         return error("Authentication failed");
//     }

//     // Query all users from Firestore
//     map<json>[]|error userDocs = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         accessToken,
//         "users",
//         {}
//     );

//     if userDocs is error {
//         log:printError("Failed to fetch users", userDocs);
//         return error("Failed to fetch user data");
//     }

//     int totalPendingUsers = 0;
//     foreach var user in userDocs {
//         if user.hasKey("status") {
//             boolean|error status = user["status"].ensureType(boolean);
//             if status is boolean && !status { // status = false (pending)
//                 totalPendingUsers += 1;
//             }
//         }
//     }

//     return totalPendingUsers;
// }



// public function getPendingUsersCount() returns int|error {
//     string|error accessToken = firebase:generateAccessToken();
//     if accessToken is error {
//         log:printError("Failed to generate access token", accessToken);
//         return error("Authentication failed");
//     }

//     // This is the correct "filter" to pass to your UNMODIFIED function.
//     // This map represents the 'where' clause of the Firestore query.
//     map<json> filterPayload = {
//         "fieldFilter": {
//             "field": { "fieldPath": "status" },
//             "op": "EQUAL",
//             "value": { "stringValue": "pending" }
//         }
//     };


//     map<json>[]|error pendingUserDocs = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         accessToken,
//         "users",
//         filterPayload
//     );

//     if pendingUserDocs is error {
//         log:printError("Failed to fetch users", pendingUserDocs);
        
//         log:printError("If you see a timeout error, ensure the Firestore index on the 'users' collection for the 'status' field is ENABLED.");
//         return error("Failed to fetch user data");
//     }

//     return pendingUserDocs.length();
// }

// Add this import at the top of your admin.bal file with other imports


public function getPendingUsersCount() returns int|error {
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        log:printError("Failed to generate access token", accessToken);
        return error("Authentication failed");
    }
    io:println("Generated access token: " + accessToken.substring(0, 10) + "...");

    io:println("=== DEBUG: Querying pending users ===");
    map<json> filter = {
        "structuredQuery": {
            "from": [{"collectionId": "users"}],
            "where": {
                "fieldFilter": {
                    "field": {"fieldPath": "status"},
                    "op": "EQUAL",
                    "value": {"stringValue": "pending"}
                }
            }
        }
    };

    map<json>[]|error result = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        accessToken,
        "users",
        filter
    );

    if result is error {
        log:printError("Filtered query failed", result);
        io:println("Falling back to manual count due to error: " + result.message());

        io:println("=== DEBUG: Falling back to fetching all users ===");
        map<json>[]|error allUsersResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "users",
            {"structuredQuery": {"from": [{"collectionId": "users"}]}}
        );

        if allUsersResult is error {
            log:printError("Cannot fetch any users", allUsersResult);
            return error("Failed to fetch users: " + allUsersResult.message());
        }

        io:println("Total users found: " + allUsersResult.length().toString());
        int manualCount = 0;
        foreach var user in allUsersResult {
            json|error statusField = user.status;

            if statusField is string {
                string statusValue = statusField;
                io:println("User status: '" + statusValue + "'");

                // --- STEP 2: REPLACE THE COMPARISON WITH THIS REGEX ---
                // This checks for "pending" case-insensitively without using toLowerCase().
                if regex:matches(statusValue.trim(), "(?i)^pending$") {
                    manualCount += 1;
                }

            } else {
                io:println("User missing status field or it's not a string.");
            }
        }
        io:println("Manual pending count: " + manualCount.toString());
        return manualCount;
    }

    io:println("Filtered pending users found: " + result.length().toString());
    return result.length();
}



