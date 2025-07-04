import 'service.firebase;
import 'service.ride_management;
import 'service.utility;
import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/log;
import 'service.auth;


// const string[] ALLOWED_IMAGE_TYPES = ["image/jpeg", "image/jpg", "image/png", "image/gif", "image/webp"];
// const int MAX_FILE_SIZE = 5 * 1024 * 1024; 

public function updateName(json payload, http:Request req, string accessToken) returns http:Response|error {
    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    string jwtToken = authHeader.substring(7);
    jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
    if tokenPayload is error {
        log:printError("Token verification failed", tokenPayload);
        return utility:createErrorResponse(401, "Invalid or expired token");
    }
    io:print(tokenPayload);

    string firstName = check payload.firstName;
    string lastName = check payload.lastName;
    string userId = <string>tokenPayload["id"];

    map<json> newUser = {
            "firstName": firstName,
            "lastName": lastName
    };

    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "users",
            userId,
            newUser
        );

    if updateResult is error {
        log:printError("Error updating name: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to update name");
    }

     map<json>|error userDoc = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            userId
    );

    string jwt;
    if userDoc is error {
        return utility:createErrorResponse(500, "Failed to update name");
    } else {
        jwt = check auth:generateAuthToken(userDoc);
    }

    json successResponse = {
        "message": "Name updated successfully"
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    response.setHeader("Authorization", "Bearer " + jwt);
    return response;
}

public function updatePhone(json payload, http:Request req, string accessToken) returns http:Response|error {
    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    string jwtToken = authHeader.substring(7);
    jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
    if tokenPayload is error {
        log:printError("Token verification failed", tokenPayload);
        return utility:createErrorResponse(401, "Invalid or expired token");
    }
    io:print(tokenPayload);

    string phone = check payload.phone;
    string userId = <string>tokenPayload["id"];

    map<json> newUser = {
        "phone": phone
    };

    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "users",
            userId,
            newUser
        );

    if updateResult is error {
        log:printError("Error updating number: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to phone");
    }

    map<json>|error userDoc = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            userId
    );

    string jwt;
    if userDoc is error {
        return utility:createErrorResponse(500, "Failed to update name");
    } else {
        jwt = check auth:generateAuthToken(userDoc);
    }

    json successResponse = {
        "message": "Phone updated successfully"
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    response.setHeader("Authorization", "Bearer " + jwt);
    return response;
}


public function updateVehicle(http:Request req) returns http:Response|error {
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    
    string vehicleBrand = check payload.vehicleBrand;
    string vehicleType = check payload.vehicleType;
    string vehicleModel = check payload.vehicleModel;
    string vehicleRegistrationNumber = check payload.vehicleRegistrationNumber;
    int seatingCapacity = check payload.seatingCapacity;

    string|error authHeader = req.getHeader("Authorization");
    if authHeader is error {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    string jwtToken = authHeader.substring(7);

    jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
    if tokenPayload is error {
        log:printError("JWT decode error: " + tokenPayload.message());
        return utility:createErrorResponse(401, "Invalid token");
    }

    string userId = <string>tokenPayload["id"];

    if userId is "" {
        return utility:createErrorResponse(401, "User ID not found in token");
    }

    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        log:printError("Failed to generate access token", accessToken);
        return utility:createErrorResponse(500, "Authentication failed");
    }

    map<json>|error userDoc = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            userId
    );

    io:print(userDoc);

    if userDoc is error {
        if userDoc.message().includes("Document not found") {
            return utility:createErrorResponse(404, "User not found");
        }
        log:printError("Error fetching user: " + userDoc.message());
        return utility:createErrorResponse(500, "Failed to fetch user details");
    }

    if userDoc.length() == 0 {
        log:printError("No document found with userId: " + userId);
        return utility:createErrorResponse(404, "User not found");
    }

    string actualDocumentId = userId; 

    map<json> updateData = {
        "driverDetails": {
            "vehicleBrand": vehicleBrand,
            "vehicleType": vehicleType,
            "vehicleModel": vehicleModel,
            "vehicleRegistrationNumber": vehicleRegistrationNumber,
            "seatingCapacity": seatingCapacity
        }
    };

    json|error updateResult = firebase:mergeFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "users", 
            actualDocumentId,
            updateData
    );

    if updateResult is error {
        log:printError("Error updating vehicle: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to update vehicle details");
    }

    
    json successResponse = {
        "message": "Vehicle details updated successfully",
        "userId": userId,
        "vehicleDetails": {
            "vehicleBrand": vehicleBrand,
            "vehicleType": vehicleType,
            "vehicleModel": vehicleModel,
            "vehicleRegistrationNumber": vehicleRegistrationNumber,
            "seatingCapacity": seatingCapacity
        }
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    return response;
    
}



// function isAllowedImageType(string contentType) returns boolean {
//     foreach string allowedType in ALLOWED_IMAGE_TYPES {
//         if contentType.toLowerAscii() == allowedType {
//             return true;
//         }
//     }
//     return false;
// }

// // Helper function to get file extension from content type
// function getFileExtension(string contentType) returns string {
//     match contentType.toLowerAscii() {
//         "image/jpeg" => {
//             return "jpg";
//         }
//         "image/jpg" => {
//             return "jpg";
//         }
//         "image/png" => {
//             return "png";
//         }
//         "image/gif" => {
//             return "gif";
//         }
//         "image/webp" => {
//             return "webp";
//         }
//         _ => {
//             return "jpg"; // Default fallback
//         }
//     }
// }



// public function uploadImage(http:Request req) returns http:Response|error {
//     // Verify authorization
//     string|error authHeader = req.getHeader("Authorization");
//     if authHeader is error {
//         return utility:createErrorResponse(401, "Authorization header missing");
//     }

//     string jwtToken = authHeader.substring(7);
//     jwt:Payload|error tokenPayload = ride_management:verifyToken(jwtToken);
//     if tokenPayload is error {
//         log:printError("JWT decode error: " + tokenPayload.message());
//         return utility:createErrorResponse(401, "Invalid token");
//     }

//     string userId = <string>tokenPayload["id"];
//     if userId is "" {
//         return utility:createErrorResponse(401, "User ID not found in token");
//     }

//     // Get multipart data
//     mime:Entity[]|error bodyParts = req.getBodyParts();
//     if bodyParts is error {
//         return utility:createErrorResponse(400, "Invalid multipart request");
//     }

//     mime:Entity? imageEntity = ();
//     string imageType = "profile"; // Default type
    
//     // Process multipart data
//     foreach mime:Entity part in bodyParts {
//         string|error contentDisposition = part.getHeader("Content-Disposition");
//         if contentDisposition is error {
//             continue;
//         }

//         if contentDisposition.includes("name=\"image\"") {
//             imageEntity = part;
//         } else if contentDisposition.includes("name=\"type\"") {
//             string|error typeValue = part.getText();
//             if typeValue is string {
//                 imageType = typeValue;
//             }
//         }
//     }

//     if imageEntity is () {
//         return utility:createErrorResponse(400, "No image file found in request");
//     }

//     // Validate content type
//     string|error contentType = imageEntity.getContentType();
//     if contentType is error {
//         return utility:createErrorResponse(400, "Unable to determine file type");
//     }

//     if !isAllowedImageType(contentType) {
//         return utility:createErrorResponse(400, "Invalid file type. Allowed types: " + ALLOWED_IMAGE_TYPES.toString());
//     }

//     // Get file data
//     byte[]|error imageData = imageEntity.getByteArray();
//     if imageData is error {
//         return utility:createErrorResponse(400, "Unable to read image data");
//     }

//     // Validate file size
//     if imageData.length() > MAX_FILE_SIZE {
//         return utility:createErrorResponse(400, "File size exceeds maximum limit of 5MB");
//     }

//     // Generate unique filename
//     string fileExtension = getFileExtension(contentType);
//     string fileName = string `${userId}_${imageType}_${uuid:createType1AsString()}.${fileExtension}`;
    
//     // Get Firebase access token
//     string|error accessToken = firebase:generateAccessToken();
//     if accessToken is error {
//         log:printError("Failed to generate access token", accessToken);
//         return utility:createErrorResponse(500, "Authentication failed");
//     }

//     // Upload to Firebase Storage
//     string|error uploadResult = firebase:uploadToStorage(
//         "carpooling-c6aa5.appspot.com", // Your Firebase Storage bucket
//         accessToken,
//         fileName,
//         imageData,
//         contentType
//     );

//     if uploadResult is error {
//         log:printError("Error uploading image: " + uploadResult.message());
//         return utility:createErrorResponse(500, "Failed to upload image");
//     }

//     // Get download URL
//     string|error downloadUrl = firebase:getDownloadUrl(
//         "carpooling-c6aa5.firebasestorage.app",
//         accessToken,
//         fileName
//     );

//     if downloadUrl is error {
//         log:printError("Error getting download URL: " + downloadUrl.message());
//         return utility:createErrorResponse(500, "Failed to get image URL");
//     }

//     // Update user document with image URL
//     map<json> updateData = {};
//     if imageType == "profile" {
//         updateData["profileImageUrl"] = downloadUrl;
//     } else if imageType == "vehicle" {
//         updateData["vehicleDetails.imageUrl"] = downloadUrl;
//     } else if imageType == "license" {
//         updateData["documents.licenseImageUrl"] = downloadUrl;
//     } else {
//         updateData[imageType + "ImageUrl"] = downloadUrl;
//     }

//     json|error updateResult = firebase:mergeFirestoreDocument(
//         "carpooling-c6aa5",
//         accessToken,
//         "users",
//         userId,
//         updateData
//     );

//     if updateResult is error {
//         log:printError("Error updating user document: " + updateResult.message());
//         return utility:createErrorResponse(500, "Image uploaded but failed to update user record");
//     }

//     // Return success response
//     json successResponse = {
//         "message": "Image uploaded successfully",
//         "imageUrl": downloadUrl,
//         "imageType": imageType,
//         "fileName": fileName,
//         "uploadTime": time:utcNow()[0]
//     };

//     http:Response response = new;
//     response.statusCode = 200;
//     response.setJsonPayload(successResponse);
//     return response;
// }

// // Helper function to check if file type is allowed

// // Helper function to get file extension from content type


// // Alternative function for profile image upload specifically
