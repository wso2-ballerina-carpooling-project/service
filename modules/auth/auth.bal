import ballerina/crypto;
import ballerina/http;
import ballerina/jwt;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerina/io;

import 'service.firebase as firebase;
import 'service.utility as utility;


configurable string keyPath = ?;
configurable string publicKey = ?;


public function generateAuthToken( map<json> user) returns string|error {

    // JWT issuer configuration
    jwt:IssuerConfig issuerConfig = {
        username: "Nalaka",
        issuer: "CarPool", 
        audience: "CarPool-App", 
        expTime: 3600,  
        customClaims: user,
        signatureConfig: {
            config: {
                keyFile: keyPath
            }
        }
    };

    // Generate the JWT token
    string jwtToken = check jwt:issue(issuerConfig);
    return jwtToken;
}

public function hashPassword(string password) returns string {
    byte[] passwordBytes = password.toBytes();
    byte[] hash = crypto:hashSha256(passwordBytes);
    return hash.toBase16();
}

public function register(@http:Payload json payload, string accessToken) returns http:Response|error {
    string email = check payload.email.ensureType();
    string password = check payload.password.ensureType();
    string firstName = check payload.firstName.ensureType();
    string lastName = check payload.lastName.ensureType();
    string phone = check payload.phone.ensureType();
    string role = check payload.role;

    // Validate required fields
    if email is "" || password is "" || firstName is "" || lastName is "" || role is "" {
        return utility:createErrorResponse(400, "Missing required fields");
    }

    // Validate role
    if role != "driver" && role != "passenger" {
        return utility:createErrorResponse(400, "Role must be 'driver' or 'passenger'");
    }

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
    string passwordHash = hashPassword(password);
    string currentTime = time:utcNow().toString();

    map<json> userData = {
        "id": userId,
        "email": email,
        "firstName": firstName,
        "lastName": lastName,
        "phone": phone,
        "role": role,
        "status": "pending",  // All new users start as pending
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


    return utility:createSuccessResponse(201, {
                                                "message": "Registration successful. Your account is pending approval by admin."
                                            });
}

public function login(@http:Payload json payload, string accessToken) returns http:Response|error {
    string? email = check payload.email.ensureType();
    string? password = check payload.password.ensureType();

    // Validate required fields
    if email is "" || password is "" {
        return utility:createErrorResponse(400, "Email and password are required");
    }

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

    if(queryResult is error){
        return utility:createErrorResponse(500,"internal server error");
    }
    if(queryResult.length() == 0){
        return utility:createErrorResponse(404,"user not found");
    }

    map<json> user;
    user = queryResult[0];

    string storedPasswordHash = <string>user["passwordHash"];
    string providedPasswordHash = hashPassword(check password.ensureType());

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
        } 
    }

    // Generate authentication token
    string|error authToken = generateAuthToken(user);
    if(authToken is error){
        io:print(authToken);
        return utility:createErrorResponse(500,"Internel server error");

    }
    // Create response with user info and token
    io:print(authToken);
    map<json> response = {
            "token": authToken,
            "role":role
        };
    
    jwt:Payload|error payloadToken = verifyToken(authToken);
    io:print(payloadToken);
    
    return utility:createSuccessResponse(200, response);
}

public function verifyToken(string jwtToken) returns jwt:Payload|error {

    jwt:ValidatorConfig validatorConfig = {
        issuer: "CarPool",
        audience: "CarPool-App",
        signatureConfig: {
            certFile: publicKey
        }
    };

    jwt:Payload payload = check jwt:validate(jwtToken, validatorConfig);

    return payload;
}
