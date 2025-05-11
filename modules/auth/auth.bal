import 'service.firebase as firebase;
import 'service.utility as utility;

import ballerina/crypto;
import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;




public function generateAuthToken(string userId, string email, string role) returns string {
    string payload = userId + ":" + email + ":" + role + ":" + time:utcNow().toString();
    string secretKey = "hello-world-sri-lanka-carpool-app";

    byte[] dataToSign = payload.toBytes();
    byte[] signature = checkpanic crypto:hmacSha256(dataToSign, secretKey.toBytes());

    return payload + "." + signature.toBase16();
}

public function hashPassword(string password) returns string {
    byte[] passwordBytes = password.toBytes();
    byte[] hash = crypto:hashSha256(passwordBytes);
    return hash.toBase16();
}

public function register(@http:Payload json payload, string accessToken) returns http:Response|error {
    string? email = check payload.email.ensureType();
    string? password = check payload.password.ensureType();
    string? firstName = check payload.firstName.ensureType();
    string? lastName = check payload.lastName.ensureType();
    string? phone = check payload.phone.ensureType();
    string? role = check payload.role.ensureType();

    // Validate required fields
    if email is () || password is () || firstName is () || lastName is () || role is () {
        return utility:createErrorResponse(400, "Missing required fields");
    }

    // Validate role
    if role != "driver" && role != "passenger" {
        return utility:createErrorResponse(400, "Role must be 'driver' or 'passenger'");
    }

    // Validate password strength
    if password.length() < 8 {
        return utility:createErrorResponse(400, "Password must be at least 8 characters long");
    }

    // Get access token

    // Check if email already exists
    map<json> emailFilter = {"email": email};
    map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "users",
            emailFilter
        );

    if queryResult is map<json>[] && queryResult.length() > 0 {
        return utility:createErrorResponse(409, "Email already registered");
    }

    // Process driver details if present
    record {|
        string? vehicleType;
        string? vehicleBrand;
        string? vehicleModel;
        string? vehicleRegistrationNumber;
        int? seatingCapacity;
    |}? vehicleData = ();

    if role == "driver" {
        var vehicleDetailsJson = payload?.vehicleDetails;

        if vehicleDetailsJson is json {
            string vehicleType = check vehicleDetailsJson.vehicleType.ensureType();
            string vehicleBrand = check vehicleDetailsJson.vehicleBrand.ensureType();
            string vehicleModel = check vehicleDetailsJson.vehicleModel.ensureType();
            string vehicleRegistrationNumber = check vehicleDetailsJson.vehicleRegistrationNumber.ensureType();
            int seatingCapacity = check vehicleDetailsJson.seatingCapacity.ensureType();

            // Validate driver details
            if vehicleType is "" || vehicleBrand is "" || vehicleModel is "" || seatingCapacity == 0 || vehicleRegistrationNumber == "" {
                return utility:createErrorResponse(400, "Driver details are incomplete");
            }

            vehicleData = {
                vehicleBrand: vehicleBrand,
                vehicleType: vehicleType,
                vehicleModel: vehicleModel,
                vehicleRegistrationNumber: vehicleRegistrationNumber,
                seatingCapacity: seatingCapacity
            };
        } else {
            return utility:createErrorResponse(400, "Driver details are required for driver role");
        }
    }

    // Create user document
    string userId = uuid:createType1AsString();
    string passwordHash = hashPassword(<string>password);
    string currentTime = time:utcNow().toString();

    map<json> userData = {
        "id": userId,
        "email": email,
        "firstName": firstName,
        "lastName": lastName,
        "phone": phone,
        "role": role,
        "status": "pending", // All new users start as pending
        "passwordHash": passwordHash,
        "driverDetails": vehicleData,
        "createdAt": currentTime
    };

    // Store in Firestore
    json|error createResult = firebase:createFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "users",
            userData
        );
    if createResult is error {
        log:printError("Failed to create user", createResult);
        return utility:createErrorResponse(500, "Failed to create user account");
    }

    // Notify about new user (in a real system, this would send an email or notification)
    // log:printInfo("New user registered: " + email + " with role: " + role);

    return utility:createSuccessResponse(201, {
                                                  "message": "Registration successful. Your account is pending approval by admin."
                                              });
}


public function login(@http:Payload json payload,string accessToken) returns http:Response|error {
        string? email = check payload.email.ensureType();
        string? password = check payload.password.ensureType();

        // Validate required fields
        if email is () || password is () {
            return utility:createErrorResponse(400, "Email and password are required");
        }

        // Get access token

        // Find user by email
        map<json> emailFilter = {"email": email};
        map<json>[]|error queryResult = firebase:queryFirestoreDocuments(
                "carpooling-c6aa5",
                accessToken,
                "users",
                emailFilter
        );

        // if queryResult is error || (queryResult is map<json>[] && queryResult.length() == 0) {
        //     return self.createErrorResponse(401, "Invalid email or password");
        // }

        map<json> user ;
        if queryResult is map<json>[] {
            user = queryResult[0];

            

        } else {
            return utility:createErrorResponse(500, "Failed to retrieve user data");
        }

        // Verify password
        string storedPasswordHash = <string>user["passwordHash"];
        string providedPasswordHash = hashPassword(<string>password);

        if storedPasswordHash != providedPasswordHash {
            return utility:createErrorResponse(401, "Invalid email or password");
        }

        // Check user status
        string status = <string>user["status"];
        string role = <string>user["role"];

        // Only allow login for admin or approved users
        if role != "admin" && status != "approved" {
            if status == "pending" {
                return utility:createErrorResponse(403, "Your account is pending approval by admin");
            } else if status == "rejected" {
                return utility:createErrorResponse(403, "Your account has been rejected");
            } else {
                return utility:createErrorResponse(403, "Your account is not active");
            }
        }

        // Generate authentication token
        string userId = <string>user["id"];
        string authToken = generateAuthToken(userId, <string>email, role);

        // Create response with user info and token
        map<json> response = {
            "id": userId,
            "email": email,
            "firstName": <string>user["firstName"],
            "lastName": <string>user["lastName"],
            "role": role,
            "status": status,
            "token": authToken
        };

        // Add driver details if available
        if user["driverDetails"] != null {
            response["driverDetails"] = user["driverDetails"];
        }

        return utility:createSuccessResponse(200, response);
    }

public function validateAuthToken(string token) returns [boolean, string, string, string]|error {
    string[] parts = re`\.`.split(token);
    
    if parts.length() != 2 {
        return error("Invalid token format");
    }
    
    string payload = parts[0];
    string providedSignature = parts[1];
    
    // Secret key must match the one used in generateAuthToken
    string secretKey = "hello-world-sri-lanka-carpool-app";
    
    // Recalculate the signature
    byte[] dataToSign = payload.toBytes();
    byte[] calculatedSignature = checkpanic crypto:hmacSha256(dataToSign, secretKey.toBytes());
    string calculatedSignatureHex = calculatedSignature.toBase16();
    
    // Compare signatures
    if providedSignature != calculatedSignatureHex {
        return [false, "", "", ""];
    }
    
    // Extract user data from payload
    string[] payloadParts = re`:`.split(payload);
    if payloadParts.length() != 4 {
        return error("Invalid payload format");
    }
    
    string userId = payloadParts[0];
    string email = payloadParts[1];
    string role = payloadParts[2];
    // string timestamp = payloadParts[3];
    
    // Optional: Check if token is expired
    // This would require parsing the timestamp and comparing with current time
    
    return [true, userId, email, role];
}




// final string JWT_SECRET = "hello-world-sri-lanka-carpool-app-secret-key";
// final decimal TOKEN_EXPIRY_SECONDS = 86400; // 24 hours

// // Generate JWT token with custom claims
// public function generateJwtToken(string userId, string email, string role) returns string|error {
//     // Current time in seconds
//     decimal issuedAt = time:utcNow()[1] / 1000;
    
//     // Set expiry time
//     decimal expiryTime = issuedAt + TOKEN_EXPIRY_SECONDS;
    
//     // Set custom claims
//     map<json> customClaims = {
//         "email": email,
//         "role": role,
//         "userId": userId
//     };
    
//     jwt:IssuerConfig issuerConfig = {
//         username: userId,
//         issuer: "carpooling-app",
//         audience: ["carpooling-app-users"],
//         keyId: "jwt-key-1",
//         expTime: expiryTime,
//         customClaims: customClaims,  // Add custom claims here
//         signatureConfig: {
//             config: {
//                 keyFile: JWT_SECRET
//             }
//         }
//     };
    
//     // Create JWT
//     return jwt:issue(issuerConfig);
// }

// // Validate JWT token
// public function validateJwtToken(string token) returns boolean|error {
//     jwt:ValidatorConfig validatorConfig = {
//         issuer: "carpooling-app",
//         audience: ["carpooling-app-users"],
//         signatureConfig: {
//             certFile: JWT_SECRET
//         }
//     };
    
//     // Validate the token
//     jwt:Payload|error payload = jwt:validate(token, validatorConfig);
    
//     if payload is error {
//         log:printError("JWT validation failed", payload);
//         return error("Invalid token");
//     }
    
//     // Extract user information from claims
//     // In Ballerina JWT, custom claims are in the customClaims field
//     // map<json>? customClaims = payload.customClaims;
    
//     // if customClaims is () {
//     //     return error("Missing claims in token");
//     // }
    
//     // // Access the claims from the customClaims map
//     // string userId = check customClaims["userId"].ensureType();
//     // string email = check customClaims["email"].ensureType();
//     // string role = check customClaims["role"].ensureType();
    
//     return true;
// }

// // Helper function to extract JWT from Authorization header
// public function extractJwtFromHeader(string authHeader) returns string|error {
//     if authHeader == "" || !authHeader.startsWith("Bearer ") {
//         return error("Invalid Authorization header format");
//     }
    
//     return authHeader.substring(7).trim();
// }

// // Example function to validate token in an API request
// public function validateRequestToken(http:Request request) returns boolean |error {
//     // Extract token from Authorization header
//     string authHeader = check request.getHeader("Authorization");
//     string token = check extractJwtFromHeader(authHeader);
    
//     // Validate the token
//     return validateJwtToken(token);
// }