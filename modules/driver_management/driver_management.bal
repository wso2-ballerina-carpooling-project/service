import ballerina/http;
import 'service.firebase;
import 'service.utility;
import ballerina/log;


// This function fetches all users with the 'driver' role and processes them.
public function getDrivers() returns http:Response|error {
    string accessToken = checkpanic firebase:generateAccessToken();
    
    map<json> driverFilter = {"role": "driver"};
    map<json>[]|error driverData = firebase:queryFirestoreDocuments("carpooling-c6aa5", accessToken, "users", driverFilter);

    if driverData is error {
        log:printError("Failed to retrieve drivers from Firestore", driverData);
        return utility:createErrorResponse(500, "Failed to retrieve drivers.");
    }

    // --- Process the raw data into the clean format the frontend expects ---
    
    // THIS IS THE FIRST MAJOR CHANGE: We build a json[] array directly.
    json[] drivers = [];
    int approvedCount = 0;
    int pendingCount = 0;
    int rejectedCount = 0;

    foreach var userData in driverData {
        string id = checkpanic userData.id.ensureType();
        string name = userData.hasKey("name") ? checkpanic userData.name.ensureType() : "N/A";
        string status = userData.hasKey("status") ? checkpanic userData.status.ensureType() : "pending";
        string registeredDate = userData.hasKey("createdAt") ? checkpanic userData.createdAt.ensureType() : "";

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

        // THIS IS THE SECOND MAJOR CHANGE: We create a map<json> for each driver.
        map<json> driverRecord = {
            id: id,
            name: name,
            vehicle: vehicle,
            registeredDate: registeredDate,
            status: status,
            licenseUrl: licenseUrl,
            registrationUrl: registrationUrl
        };
        // We push this map<json> into our json[] array. This is perfectly valid.
        drivers.push(driverRecord);

        // Calculate stats
        if status == "approved" {
            approvedCount += 1;
        } else if status == "pending" {
            pendingCount += 1;
        } else if status == "rejected" {
            rejectedCount += 1;
        }
    }

    // THIS IS THE FINAL FIX: `drivers` is already a json[] array. NO CASTING IS NEEDED.
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

// This function remains the same, as it was already correct.
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