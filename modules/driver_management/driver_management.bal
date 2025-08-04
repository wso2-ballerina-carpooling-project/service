import ballerina/http;
import 'service.firebase;
import 'service.utility;
import ballerina/log;
import ballerina/time; // The time module is correctly imported

// This function fetches all users with the 'driver' role and processes them.
public function getDrivers() returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();
    
    map<json> driverFilter = {"role": "driver"};
    map<json>[]|error driverData = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "users", driverFilter);

    if driverData is error {
        log:printError("Failed to retrieve drivers from Firestore", driverData);
        return utility:createErrorResponse(500, "Failed to retrieve drivers.");
    }
    
    json[] drivers = [];
    int approvedCount = 0;
    int pendingCount = 0;
    int rejectedCount = 0;

    foreach var userData in driverData {
        string id = checkpanic userData.id.ensureType();
        
        string firstName = userData.hasKey("firstName") ? checkpanic userData.firstName.ensureType() : "";
        string lastName = userData.hasKey("lastName") ? checkpanic userData.lastName.ensureType() : "";
        string name = (firstName + " " + lastName).trim();
        if name == "" {
            name = "N/A";
        }
        
        string status = userData.hasKey("status") ? checkpanic userData.status.ensureType() : "pending";

        // --- THIS IS THE FIX: ADDED THE EMAIL LOGIC ---
        string email = userData.hasKey("email") ? checkpanic userData.email.ensureType() : "N/A";

        // --- Date Handling Logic (already correct) ---
        string registeredDate = "N/A";
        if (userData.hasKey("createdAt") && userData.createdAt is map<json>) {
            map<json> tsMap = checkpanic userData.createdAt.ensureType();
            int seconds = checkpanic tsMap["_seconds"].ensureType();

            time:Utc utcTime = [seconds, 0.0d];


            time:Civil civilTime = time:utcToCivil(utcTime);
            

            registeredDate = string `${civilTime.year}-${civilTime.month.toString().padStart(2, "0")}-${civilTime.day.toString().padStart(2, "0")}`;
        }

        string vehicleModel = "N/A";
        string licenseNumber = "";
        string licenseUrl = "#";
        string registrationUrl = "#";

        if userData.hasKey("driverDetails") && userData.driverDetails is map<json> {
            map<json> details = checkpanic userData.driverDetails.ensureType();
            vehicleModel = details.hasKey("vehicleModel") ? checkpanic details.vehicleModel.ensureType() : "N/A";
            licenseNumber = details.hasKey("licenseNumber") ? checkpanic details.licenseNumber.ensureType() : "";
            licenseUrl = details.hasKey("licensePhotoUrl") ? checkpanic details.licensePhotoUrl.ensureType() : "#";
            registrationUrl = details.hasKey("vehicleRegistrationUrl") ? checkpanic details.vehicleRegistrationUrl.ensureType() : "#";
        }
        
        string vehicle = string `${vehicleModel} - ${licenseNumber}`;


        map<json> driverRecord = {
            id: id,
            name: name,
            email: email, // --- THIS IS THE FIX: ADDED EMAIL TO THE RESPONSE ---
            vehicle: vehicle,
            registeredDate: registeredDate,
            status: status,
            licenseUrl: licenseUrl,
            registrationUrl: registrationUrl
        };
        
        drivers.push(driverRecord);


        if status == "approved" {
            approvedCount += 1;
        } else if status == "pending" {
            pendingCount += 1;
        } else if status == "rejected" {
            rejectedCount += 1;
        }
    }
    

    map<json> responseData = {
        drivers: drivers,
        stats: {
            approvedDrivers: approvedCount,
            pendingDrivers: pendingCount,
            rejectedDrivers: rejectedCount
        }
    };

    return utility:createSuccessResponse(200, responseData);
}

// The updateDriverStatus function does not need any changes.
public function updateDriverStatus(json payload, string newStatus) returns http:Response|error {
    string|error driverId = payload.driverId.ensureType();
    if driverId is error {
        return utility:createErrorResponse(400, "driverId is required in the payload.");
    }

    string accessToken = checkpanic firebase:generateAccessToken();
    map<json> updateData = {"status": newStatus};

    json|error updateResult = firebase:mergeFirestoreDocument(
        "carpooling-c6aa5",
        accessToken,
        "users",
        driverId,
        updateData
    );

    if updateResult is error {
        log:printError("Failed to update driver status", updateResult);
        return utility:createErrorResponse(500, "Failed to update driver status.");
    }

    return utility:createSuccessResponse(200, {"message": "Driver status updated to " + newStatus});
}