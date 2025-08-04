import ballerina/http;
import 'service.firebase;
import 'service.utility;
import ballerina/log;
import ballerina/time; // NEW: Import the 'time' module

// This function fetches all users with the 'passenger' role and processes them.
public function getPassengers() returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();
    
    // --- CHANGE #1: SIMPLIFIED, EFFICIENT QUERY ---
    // We fetch all users with the role "passenger" in a single query.
    map<json> passengerFilter = {"role": "passenger"};
    map<json>[]|error passengerData = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "users", passengerFilter);

    if passengerData is error {
        log:printError("Failed to retrieve passengers from Firestore", passengerData);
        return utility:createErrorResponse(500, "Failed to retrieve passengers.");
    }
    
    json[] passengers = [];
    int approvedCount = 0;
    int pendingCount = 0;
    int rejectedCount = 0;

    foreach var userData in passengerData {
        string id = checkpanic userData.id.ensureType();
        
        // --- FIX #1: CONSTRUCT THE FULL NAME ---
        string firstName = userData.hasKey("firstName") ? checkpanic userData.firstName.ensureType() : "";
        string lastName = userData.hasKey("lastName") ? checkpanic userData.lastName.ensureType() : "";
        string name = (firstName + " " + lastName).trim();
        if name == "" {
            name = "N/A";
        }
        
        string status = userData.hasKey("status") ? checkpanic userData.status.ensureType() : "pending";
        string email = userData.hasKey("email") ? checkpanic userData.email.ensureType() : "N/A";

        // --- FIX #2: HANDLE THE TIMESTAMP CORRECTLY ---
        string registeredDate = "N/A";
        if (userData.hasKey("createdAt") && userData.createdAt is map<json>) {
            map<json> tsMap = checkpanic userData.createdAt.ensureType();
            int seconds = checkpanic tsMap["_seconds"].ensureType();
            
            // Step 1: Create the Utc tuple directly. This is the correct method for your environment.
            time:Utc utcTime = [seconds, 0.0d];

            // Step 2: Convert the Utc tuple to a calendar-based Civil record.
            time:Civil civilTime = time:utcToCivil(utcTime);

            // Step 3: Format the string.
            registeredDate = string `${civilTime.year}-${civilTime.month.toString().padStart(2, "0")}-${civilTime.day.toString().padStart(2, "0")}`;
        }

        // Create the record for this passenger.
        map<json> passengerRecord = {
            id: id,
            name: name,
            email: email,
            status: status,
            registeredDate: registeredDate
        };
        
        passengers.push(passengerRecord);

        // Calculate stats in the same loop for efficiency.
        if status == "approved" {
            approvedCount += 1;
        } else if status == "pending" {
            pendingCount += 1;
        } else if status == "rejected" {
            rejectedCount += 1;
        }
    }


    map<json> responseData = {
        passengers: passengers,
        stats: {
            approvedPassengers: approvedCount,
            pendingPassengers: pendingCount,
            rejectedPassengers: rejectedCount
        }
    };

    return utility:createSuccessResponse(200, responseData);
}

// The updatePassengerStatus function does not need any changes.
public function updatePassengerStatus(json payload, string newStatus) returns http:Response|error {
    // Note: The frontend page expects 'passengerId' as the key.
    string|error passengerId = payload.passengerId.ensureType();
    if passengerId is error {
        return utility:createErrorResponse(400, "passengerId is required in the payload.");
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