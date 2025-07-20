import 'service.firebase;

import ballerina/log;
import ballerina/time;
import 'service.utility;
import ballerina/http;
import ballerina/io;

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


// Response record for user earnings
public type UserEarningsResponse record {
    string userId;
    decimal pendingEarnings;
    decimal totalEarnings;
    int rideCount;
    string currency;
    string timestamp;
};

// Error response record
public type ErrorResponse record {
    string message;
    string timestamp;
};

public function getUserEarnings(string userId) returns http:Response|ErrorResponse {
    
    // Generate access token with proper error handling
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        log:printError("Failed to generate access token", accessToken);
        return {
            message: "Authentication failed",
            timestamp: time:utcToString(time:utcNow())
        };
    }
    
    // Query for all payment records for this user
    map<json> queryFilter = {"user": userId};
    
    map<json>[]|error paymentDocs = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        accessToken,
        "payments",
        queryFilter
    );

    if paymentDocs is error {
        log:printError("Failed to query payment documents");
        return {
            message: "Failed to fetch payment data",
            timestamp: time:utcToString(time:utcNow())
        };
    }

    // Initialize counters
    decimal pendingEarnings = 0.0d;
    decimal totalEarnings = 0.0d;
    int rideCount = paymentDocs.length();
    int pendingPaymentRideCount = 0;

    // Process each payment record
    foreach map<json> payment in paymentDocs {
        
        // Extract amount
        json amountJson = payment["amount"];
        decimal amount = 0.0d;
        
  
        decimal|error parsedAmount = decimal:fromString(<string>amountJson);
        if parsedAmount is decimal {
            amount = parsedAmount;
        }
        
        // Add to total earnings
        totalEarnings += amount;
        
        // Check if payment is pending (not paid)
        boolean isPaid = <boolean>payment["isPaid"];
        io:print(isPaid);

        
        
        
        // If not paid, add to pending earnings
        if !isPaid {
            pendingEarnings += amount;
            pendingPaymentRideCount+=1;
        }
    }

    log:printInfo(string `User earnings calculated - UserId: ${userId}, Total: ${totalEarnings}, Pending: ${pendingEarnings}, Rides: ${rideCount}`);


    return utility:createSuccessResponse(200,{"userId":userId,"pendingEarnings":pendingEarnings,"totalEarnings":totalEarnings,"totalRideCount":rideCount,"pendingPaymentRideCount":pendingPaymentRideCount});
}

