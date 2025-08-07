import 'service.firebase;
import 'service.utility;

import ballerina/email;
import ballerina/http;
import ballerina/log;
import ballerina/time; // The time module is correctly imported

// This function fetches all users with the 'driver' role and processes them.

email:SmtpClient smtpClient = check new (
    host = "smtp.gmail.com",
    port = 465,
    username = "nalakadineshx@gmail.com",
    password = "ihuv sgsh ddng ljfu",
    security = email:SSL
);

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
    map<json>|error userDoc = firebase:getFirestoreDocumentById(
        "carpooling-c6aa5",
        accessToken,
        "users",
        driverId
        );
    if userDoc is error {
        if userDoc.message().includes("Document not found") {
            return utility:createErrorResponse(404, "user not found");
        }
        return utility:createErrorResponse(500, "Failed to fetch user details");
    }

    if userDoc.length() == 0 {
        return utility:createErrorResponse(404, "user not found");
    }

    string actualDocumentId = <string>userDoc["id"];
    string email = check userDoc["email"].ensureType();
    map<json> updateData = {"status": newStatus};

    json|error updateResult = firebase:mergeFirestoreDocument(
        "carpooling-c6aa5",
        accessToken,
        "users",
        actualDocumentId,
        updateData
    );

    if updateResult is error {
        log:printError("Failed to update driver status", updateResult);
        return utility:createErrorResponse(500, "Failed to update driver status.");
    }
    if(newStatus=="approved"){
         email:Message emailMessage = {
                to: [email],
                subject: "Your account is approved.",
                body: string `
                    <html>
                    <body>
                        <h2>Your Carpool account was activated.</h2>
                        <p>Your registration requested to CarPool approved by CarPool Administration.</p>
                        <p></p>
                        <p>You can use CarPool service now.</p>
                        <p>Happy to see you in here.</p>
                        <br>
                        <p>Best regards,<br>Carpool Team</p>
                    </body>
                    </html>
                `
            };

            email:Error? emailResult = smtpClient->sendMessage(emailMessage);
    }else{
        email:Message emailMessage = {
                to: [email],
                subject: "Your account is rejected.",
                body: string `
                    <html>
                    <body>
                        <h2>Your Carpool account was rejected by admin.</h2>
                        <p>Your registration requested to CarPool rejected by CarPool Administration.Please contact CarPool administration.</p>
                        <br>
                        <p>Best regards,<br>Carpool Team</p>
                    </body>
                    </html>
                `
            };

            email:Error? emailResult = smtpClient->sendMessage(emailMessage);
    }

    return utility:createSuccessResponse(200, {"message": "Driver status updated to " + newStatus});
}
