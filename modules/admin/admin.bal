// import ballerina/io;
// import ballerina/log;
// import ballerina/time;
// import ballerina/regex;
// import 'service.firebase as firebase; 
// import ballerina/http;
import ballerina/http;
import 'service.firebase;
import 'service.utility;


// public function getBookedRidesWithinDay(http:Request req) returns http:Response|error {
//     string|error firebaseAccessToken = firebase:generateAccessToken();
//     if firebaseAccessToken is error {
//         log:printError("Failed to generate access token", firebaseAccessToken);
//         return error("Authentication failed");
//     }

//     map<json> queryFilter = {"rideId": "date"};



    

//     // Query filtered rides from Firestore
//     map<json>[]|error rideDocs = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         firebaseAccessToken,
//         "rides",
//         queryFilter
//     );

//     if rideDocs is error {
//         log:printError("Failed to fetch rides", rideDocs);
//         return error("Failed to fetch ride data");
//     }

//     int totalBookedRides = 0;
//     foreach var ride in rideDocs {
//         if ride.hasKey("passengers") {
//             json passengersJson = ride["passengers"];
//             if passengersJson is json[] {
//                 json[] passengers = <json[]>passengersJson;
//                 boolean hasConfirmedPassenger = false;
//                 foreach var passenger in passengers {
//                     if passenger is map<json> && passenger.hasKey("status") {
//                         string|error passengerStatus = passenger["status"].ensureType(string);
//                         if passengerStatus is string && passengerStatus == "confirmed" {
//                             hasConfirmedPassenger = true;
//                             break;
//                         }
//                     }
//                 }
//                 if hasConfirmedPassenger {
//                     totalBookedRides += 1;
//                 }
//             }
//         }
//     }

//     return totalBookedRides;
// }


// //cancelled rides
// public function getDriverCanceledRidesWithinDay() returns int|error {
//     string|error firebaseAccessToken = firebase:generateAccessToken();
//     if firebaseAccessToken is error {
//         log:printError("Failed to generate access token", firebaseAccessToken);
//         return error("Authentication failed");
//     }

//     // Get current time and calculate 24 hours ago
//     int currentTime = time:utcNow()[0]; // Current time in seconds
//     int twentyFourHoursAgo = currentTime - (24 * 60 * 60); // 24 hours in seconds

//     // Query rides with status "cancelled" from Firestore
//     map<json> queryFilter = {"status": "cancelled"};
//     map<json>[]|error rideDocs = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         firebaseAccessToken,
//         "rides",
//         queryFilter
//     );

//     if rideDocs is error {
//         log:printError("Failed to fetch rides", rideDocs);
//         return error("Failed to fetch ride data");
//     }

//     int totalCanceledRides = 0;
//     foreach var ride in rideDocs {
//         if ride.hasKey("updatedAt") {
//             int|error updatedAt = ride["updatedAt"].ensureType(int);
//             if updatedAt is int && updatedAt >= twentyFourHoursAgo {
//                 totalCanceledRides += 1;
//             }
//         }
//     }

//     return totalCanceledRides;
// }

// // new users
// // public function getPendingUsersCount() returns int|error {
// //     string|error accessToken = firebase:generateAccessToken();
// //     if accessToken is error {
// //         log:printError("Failed to generate access token", accessToken);
// //         return error("Authentication failed");
// //     }

// //     // Query all users from Firestore
// //     map<json>[]|error userDocs = firebase:queryFirestoreDocuments(
// //         "carpooling-c6aa5",
// //         accessToken,
// //         "users",
// //         {}
// //     );

// //     if userDocs is error {
// //         log:printError("Failed to fetch users", userDocs);
// //         return error("Failed to fetch user data");
// //     }

// //     int totalPendingUsers = 0;
// //     foreach var user in userDocs {
// //         if user.hasKey("status") {
// //             boolean|error status = user["status"].ensureType(boolean);
// //             if status is boolean && !status { // status = false (pending)
// //                 totalPendingUsers += 1;
// //             }
// //         }
// //     }

// //     return totalPendingUsers;
// // }



// // public function getPendingUsersCount() returns int|error {
// //     string|error accessToken = firebase:generateAccessToken();
// //     if accessToken is error {
// //         log:printError("Failed to generate access token", accessToken);
// //         return error("Authentication failed");
// //     }

// //     // This is the correct "filter" to pass to your UNMODIFIED function.
// //     // This map represents the 'where' clause of the Firestore query.
// //     map<json> filterPayload = {
// //         "fieldFilter": {
// //             "field": { "fieldPath": "status" },
// //             "op": "EQUAL",
// //             "value": { "stringValue": "pending" }
// //         }
// //     };


// //     map<json>[]|error pendingUserDocs = firebase:queryFirestoreDocuments(
// //         "carpooling-c6aa5",
// //         accessToken,
// //         "users",
// //         filterPayload
// //     );

// //     if pendingUserDocs is error {
// //         log:printError("Failed to fetch users", pendingUserDocs);
        
// //         log:printError("If you see a timeout error, ensure the Firestore index on the 'users' collection for the 'status' field is ENABLED.");
// //         return error("Failed to fetch user data");
// //     }

// //     return pendingUserDocs.length();
// // }

// // Add this import at the top of your admin.bal file with other imports


// public function getPendingUsersCount() returns int|error {
//     string|error accessToken = firebase:generateAccessToken();
//     if accessToken is error {
//         log:printError("Failed to generate access token", accessToken);
//         return error("Authentication failed");
//     }
//     io:println("Generated access token: " + accessToken.substring(0, 10) + "...");

//     io:println("=== DEBUG: Querying pending users ===");
//     map<json> filter = {
//         "structuredQuery": {
//             "from": [{"collectionId": "users"}],
//             "where": {
//                 "fieldFilter": {
//                     "field": {"fieldPath": "status"},
//                     "op": "EQUAL",
//                     "value": {"stringValue": "pending"}
//                 }
//             }
//         }
//     };

//     map<json>[]|error result = firebase:queryFirestoreDocuments(
//         "carpooling-c6aa5",
//         accessToken,
//         "users",
//         filter
//     );

//     if result is error {
//         log:printError("Filtered query failed", result);
//         io:println("Falling back to manual count due to error: " + result.message());

//         io:println("=== DEBUG: Falling back to fetching all users ===");
//         map<json>[]|error allUsersResult = firebase:queryFirestoreDocuments(
//             "carpooling-c6aa5",
//             accessToken,
//             "users",
//             {"structuredQuery": {"from": [{"collectionId": "users"}]}}
//         );

//         if allUsersResult is error {
//             log:printError("Cannot fetch any users", allUsersResult);
//             return error("Failed to fetch users: " + allUsersResult.message());
//         }

//         io:println("Total users found: " + allUsersResult.length().toString());
//         int manualCount = 0;
//         foreach var user in allUsersResult {
//             json|error statusField = user.status;

//             if statusField is string {
//                 string statusValue = statusField;
//                 io:println("User status: '" + statusValue + "'");

//                 // --- STEP 2: REPLACE THE COMPARISON WITH THIS REGEX ---
//                 // This checks for "pending" case-insensitively without using toLowerCase().
//                 if regex:matches(statusValue.trim(), "(?i)^pending$") {
//                     manualCount += 1;
//                 }

//             } else {
//                 io:println("User missing status field or it's not a string.");
//             }
//         }
//         io:println("Manual pending count: " + manualCount.toString());
//         return manualCount;
//     }

//     io:println("Filtered pending users found: " + result.length().toString());
//     return result.length();
// }




public function rides() returns http:Response|error {
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }
    
    // Try to get all rides by querying for a field that should exist in most documents
    // Based on your other code, let's try with date field which is commonly used
    map<json> queryFilter = {
        "waytowork": true  // Query for rides going to work
    };
    
    map<json>[]|error workRides = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );
    
    // Also get rides going from work
    map<json> homeQueryFilter = {
        "waytowork": false  // Query for rides going home
    };
    
    map<json>[]|error homeRides = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            homeQueryFilter
    );
    
    // Combine both results
    map<json>[] allRides = [];
    
    if workRides is map<json>[] {
        foreach var ride in workRides {
            allRides.push(ride);
        }
    }
    
    if homeRides is map<json>[] {
        foreach var ride in homeRides {
            allRides.push(ride);
        }
    }
    
    // If both queries failed, return error with more info
    if workRides is error && homeRides is error {
        return utility:createErrorResponse(500, "Failed to fetch any rides. Work rides error: " + workRides.message() + " | Home rides error: " + homeRides.message());
    }
    
    return utility:createSuccessResponse(200, {
        "rides": allRides, 
        "count": allRides.length(),
        "workRidesCount": workRides is map<json>[] ? workRides.length() : 0,
        "homeRidesCount": homeRides is map<json>[] ? homeRides.length() : 0
    });

}




public function users() returns http:Response|error {
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }
    
    // Try to get all rides by querying for a field that should exist in most documents
    // Based on your other code, let's try with date field which is commonly used
    map<json> queryFilter = {
        "role": "driver"  // Query for rides going to work
    };
    
    map<json>[]|error workRides = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "users",
            queryFilter
    );
    
    // Also get rides going from work
    map<json> pQueryFilter = {
        "role": "passenger"  // Query for rides going home
    };
    
    map<json>[]|error homeRides = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "users",
            pQueryFilter
    );
    
    // Combine both results
    map<json>[] allUsers = [];
    
    if workRides is map<json>[] {
        foreach var ride in workRides {
            allUsers.push(ride);
        }
    }
    
    if homeRides is map<json>[] {
        foreach var ride in homeRides {
            allUsers.push(ride);
        }
    }
    
    // If both queries failed, return error with more info
    if workRides is error && homeRides is error {
        return utility:createErrorResponse(500, "Failed to fetch any rides. Work rides error: " + workRides.message() + " | Home rides error: " + homeRides.message());
    }
    
    return utility:createSuccessResponse(200, {
        "users": allUsers, 
        "count": allUsers.length(),
        "drivers": workRides is map<json>[] ? workRides.length() : 0,
        "passengers": homeRides is map<json>[] ? homeRides.length() : 0
    });

}





public function payments() returns http:Response|error {
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }
    
    // Try to get all rides by querying for a field that should exist in most documents
    // Based on your other code, let's try with date field which is commonly used
    map<json> queryFilter = {
        "isPaid": true  // Query for rides going to work
    };
    
    map<json>[]|error workRides = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "payments",
            queryFilter
    );
    
    // Also get rides going from work
    map<json> pQueryFilter = {
        "isPaid": false  // Query for rides going home
    };
    
    map<json>[]|error homeRides = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "payments",
            pQueryFilter
    );
    
    // Combine both results
    map<json>[] allUsers = [];
    
    if workRides is map<json>[] {
        foreach var ride in workRides {
            allUsers.push(ride);
        }
    }
    
    if homeRides is map<json>[] {
        foreach var ride in homeRides {
            allUsers.push(ride);
        }
    }
    
    // If both queries failed, return error with more info
    if workRides is error && homeRides is error {
        return utility:createErrorResponse(500, "Failed to fetch any rides. Work rides error: " + workRides.message() + " | Home rides error: " + homeRides.message());
    }
    
    return utility:createSuccessResponse(200, {
        "payment": allUsers, 
        "count": allUsers.length(),
        "payeed": workRides is map<json>[] ? workRides.length() : 0,
        "notpayeed": homeRides is map<json>[] ? homeRides.length() : 0
    });

}


