import ballerina/http;
import 'service.firebase;
import 'service.utility;
import ballerina/log;

// Defines the structure for a single passenger's data
public type Passenger record {
    string id;
    string name;
    string email;
    string status;
};

// This function is now PUBLIC so service.bal can see it.
// This function is now PUBLIC so service.bal can see it.
// This function is now PUBLIC so service.bal can see it.
// This function is PUBLIC so service.bal can see it.
public function getPassengers() returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();
    
    // --- WORKAROUND LOGIC ---
    map<json>[] allUsers = [];

    map<json>[]|error pendingResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "users", {"status": "pending"});
    if pendingResult is map<json>[] {
        allUsers.push(...pendingResult);
    } else {
        log:printError("Failed to retrieve PENDING passengers", pendingResult);
    }

    map<json>[]|error approvedResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "users", {"status": "approved"});
    if approvedResult is map<json>[] {
        allUsers.push(...approvedResult);
    } else {
        log:printError("Failed to retrieve APPROVED passengers", approvedResult);
    }

    map<json>[]|error rejectedResult = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "users", {"status": "rejected"});
     if rejectedResult is map<json>[] {
        allUsers.push(...rejectedResult);
    } else {
        log:printError("Failed to retrieve REJECTED passengers", rejectedResult);
    }
    
    // --- De-duplication and Final Processing ---
    
    // THIS IS THE FIRST MAJOR CHANGE: We will build a json[] array directly.
    json[] finalPassengerList = [];
    map<json> uniqueUserIds = {}; // To track IDs we've already added

    foreach var userData in allUsers {
        string id = checkpanic userData.id.ensureType();
        
        // Check if we have already processed this user ID
        if !uniqueUserIds.hasKey(id) {
            // It's a new user, add them to the list and mark the ID as seen
            finalPassengerList.push(userData);
            uniqueUserIds[id] = true; // Mark as seen
        }
    }

    // THIS IS THE SECOND MAJOR CHANGE: We will calculate stats from the final list.
    int approvedCount = 0;
    int pendingCount = 0;

    foreach var p in finalPassengerList {
        if p is map<json> && p.hasKey("status") {
            if p.status == "approved" {
                approvedCount += 1;
            } else if p.status == "pending" {
                pendingCount += 1;
            }
        }
    }

    // THIS IS THE FINAL FIX: Both `finalPassengerList` and `stats` are already json types.
    // No casting is needed at all.
    map<json> responseData = {
        passengers: finalPassengerList,
        stats: {
            approvedCount: approvedCount,
            pendingCount: pendingCount
        }
    };

    return utility:createSuccessResponse(200, responseData);
}


public function updatePassengerStatus(json payload, string newStatus) returns http:Response|error {
    string|error passengerId = payload.passengerId.ensureType();
    if passengerId is error {
        return utility:createErrorResponse(400, "Passenger ID is required in the payload.");
    }

    string accessToken = checkpanic firebase:generateAccessToken();
    map<json> updateData = {"status": newStatus};

    json|error updateResult = firebase:mergeFirestoreDocument(
        "carpooling-c6aa5",
        accessToken,
        "users",
        passengerId,
        updateData
    );

    if updateResult is error {
        log:printError("Failed to update passenger status in Firestore", updateResult);
        return utility:createErrorResponse(500, "Failed to update passenger status.");
    }

    return utility:createSuccessResponse(200, {"message": "Passenger status updated to " + newStatus});
}