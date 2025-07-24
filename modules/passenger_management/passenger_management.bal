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
public function getPassengers() returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();
    
    map<json>[]|error usersData = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "users", {});

    if usersData is error {
        log:printError("Failed to retrieve passengers from Firestore", usersData);
        return utility:createErrorResponse(500, "Failed to retrieve passengers.");
    }

    Passenger[] passengers = [];
    int approvedCount = 0;
    int pendingCount = 0;

    foreach var userData in usersData {
        string id = checkpanic userData.id.ensureType();
        string name = checkpanic userData.name.ensureType();
        string email = checkpanic userData.email.ensureType();
        
        string status = "pending";
        if userData.hasKey("status") {
            status = checkpanic userData.status.ensureType();
        }

        passengers.push({id, name, email, status});

        if status == "approved" {
            approvedCount += 1;
        } else if status == "pending" {
            pendingCount += 1;
        }
    }

    // This creates a generic JSON map, which is what the utility function expects.
    map<json> responseData = {
        passengers: <json>passengers,
        stats: {
            approvedCount: approvedCount,
            pendingCount: pendingCount
        }
    };

    return utility:createSuccessResponse(200, responseData);
}

// This function is now PUBLIC so service.bal can see it.
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