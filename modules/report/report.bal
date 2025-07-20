import 'service.firebase;

import ballerina/log;
import ballerina/time;

public function paymentUpdate(string rideId) {

    // Generate access token with proper error handling
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        log:printError("Failed to generate access token");
        return;
    }

    map<json> queryFilter = {"rideId": rideId};

    // Query for the specific ride document
    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "rides",
            queryFilter
    );

    if rideDoc is error {
        log:printError("Failed to query ride documents", rideDoc);
        return;
    }

    if rideDoc.length() == 0 {
        log:printError("No ride found with ID: " + rideId);
        return;
    }

    decimal totalEarnings = 0.0d;

    json passengersJson = rideDoc[0]["passengers"];
    if passengersJson is json[] {
        json[] passengers = <json[]>passengersJson;
        foreach json passenger in passengers {
            if passenger is map<json> {
                // Verify passenger has required fields
                if passenger.hasKey("passengerId") && passenger.hasKey("cost") {
                    json costJson = passenger["cost"];

                    decimal|error parsedCost = decimal:fromString(<string>costJson);
                    if parsedCost is decimal {
                        totalEarnings += parsedCost;
                    } else {
                        log:printWarn("Failed to parse cost string: " + <string>costJson);
                    }

                }
            }
        }
    } else {
        log:printWarn("Passengers field is not an array or is null");
    }

    // Extract driver ID with proper type checking
    json driverIdJson = rideDoc[0]["driverId"];
    if !(driverIdJson is string) {
        log:printError("Driver ID is not a valid string");
        return;
    }
    string driverId = <string>driverIdJson;

    // Check if payment already exists to avoid duplicates
    map<json> paymentQuery = {
        "user": driverId,
        "ride": rideId
    };

    map<json>[]|error existingPayments = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "payments",
            paymentQuery
    );

    if existingPayments is error {
        log:printError("Failed to check existing payments", existingPayments);
        return;
    }

    if existingPayments.length() > 0 {
        log:printInfo("Payment record already exists for ride: " + rideId);
        return; // Payment already exists, no need to create duplicate
    }

    // Create payment record
    map<json> paymentData = {
        "user": driverId,
        "ride": rideId,
        "amount": totalEarnings,
        "isPaid": false,  // Fixed typo: "isPayed" -> "isPaid"
        "createdAt": time:utcNow()
    };

    json|error createResult = firebase:createFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "payments",
            paymentData
    );

    if createResult is error {
        log:printError("Failed to create payment document", createResult);
        return;
    }

    log:printInfo("Payment record created successfully for ride: " + rideId +
                ", driver: " + driverId + ", amount: " + totalEarnings.toString());
}

public function driverEarning(string id) {

}
