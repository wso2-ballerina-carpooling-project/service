import ballerina/log;
import ballerina/time;
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



public function getPendingUsersCount() returns int|error {
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        log:printError("Failed to generate access token", accessToken);
        return error("Authentication failed");
    }

    // This is the correct "filter" to pass to your UNMODIFIED function.
    // This map represents the 'where' clause of the Firestore query.
    map<json> filterPayload = {
        "fieldFilter": {
            "field": { "fieldPath": "status" },
            "op": "EQUAL",
            "value": { "stringValue": "pending" }
        }
    };


    map<json>[]|error pendingUserDocs = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        accessToken,
        "users",
        filterPayload
    );

    if pendingUserDocs is error {
        log:printError("Failed to fetch users", pendingUserDocs);
        
        log:printError("If you see a timeout error, ensure the Firestore index on the 'users' collection for the 'status' field is ENABLED.");
        return error("Failed to fetch user data");
    }

    return pendingUserDocs.length();
}


// payment ststus
type Payment record {|
    string id;
    decimal amount;
    boolean isPaid;
    string customerName;
    // The date of the transaction in "YYYY-MM-DD" format.
    string transactionDate; 
|};

// Defines the structure of the JSON response for payment statistics.
type PaymentStats record {|
    decimal completedPercentage;
    decimal pendingPercentage;
|};



 function calculatePaymentStats(Payment[] payments) returns PaymentStats {
    int totalCount = payments.length();

    // Prevent division by zero error if the list is empty.
    if totalCount == 0 {
        return {
            completedPercentage: 0.0,
            pendingPercentage: 0.0
        };
    }

    // Use a query expression to count completed payments (isPaid = true).
    int completedCount = (from Payment p in payments where p.isPaid select p).length();
    
    // Calculate pending payments.
    int pendingCount = totalCount - completedCount;

    // Cast integers to decimal for floating-point division. This is the corrected syntax.
    decimal completedPercentage = (<decimal>completedCount / <decimal>totalCount) * 100;
    decimal pendingPercentage = (<decimal>pendingCount / <decimal>totalCount) * 100;

    return {
        completedPercentage: completedPercentage.round(2),
        pendingPercentage: pendingPercentage.round(2)
    };

    
}



    