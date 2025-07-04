import 'service.firebase_auth;

import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/regex;
import ballerina/time;


configurable string privateKeyFilePath = ?;
configurable string tokenScope = ?;
configurable firebase_auth:ServiceAccount serviceAccount = ?;

public function generateAccessToken() returns string|error {
    firebase_auth:AuthConfig authConfig = {
        privateKeyPath: privateKeyFilePath,
        jwtConfig: {
            expTime: 3600,
            scope: tokenScope
        },
        serviceAccount: serviceAccount
    };

    firebase_auth:Client authClient = check new (authConfig);
    string|error token = authClient.generateToken();
    if token is error {
        log:printError("Failed to obtain access token", token);
        return error("Failed to obtain access token");
    }
    return token;
}

public function createFirestoreDocument(
        string projectId,
        string accessToken,
        string collection,
        map<json> documentData
) returns error? {
    string firestoreUrl = string `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}`;

    http:Client firestoreClient = check new (firestoreUrl);
    http:Request request = new;

    request.setHeader("Authorization", string `Bearer ${accessToken}`);
    request.setHeader("Content-Type", "application/json");

    map<map<json>> firestoreFields = {};
    foreach var [key, value] in documentData.entries() {
        firestoreFields[key] = processFirestoreValue(value);
    }

    json payload = {
        fields: firestoreFields
    };

    request.setJsonPayload(payload);

    http:Response response = check firestoreClient->post("", request);

    io:println(response);

}

function isTimestampString(string value) returns boolean {
    // Basic check for ISO 8601 format (YYYY-MM-DDTHH:MM:SS.sssZ or similar)
    return value.length() >= 19 &&
            value.includes("T") &&
            (value.endsWith("Z") || value.includes("+") || value.includes("-", value.length() - 6));
}

function isUnixTimestamp(int value) returns boolean {
    // Unix timestamps are typically between 1970 and far future
    // This checks if the value is in a reasonable range for timestamps
    return value > 946684800 && value < 4102444800; // 2000-01-01 to 2100-01-01
}

public function processFirestoreValue(json value) returns map<json> {

    if value is string {
        if (isTimestampString(value)) {
            return {"timestampValue": value};
        }

        return {"stringValue": value};
        } else if value is int {
            if (isUnixTimestamp(value)) {
            // Convert Unix timestamp to ISO 8601 string
                time:Utc utcTime = [value, 0];
                string isoString = time:utcToString(utcTime);
                return {"timestampValue": isoString};
            }
            return {"integerValue": value};
        } else if value is boolean {
            return {"booleanValue": value};
        } else if value is () {
            return {"nullValue": null};
        } else if value is map<json> {
            if (value.hasKey("_timestamp") && value["_timestamp"] is boolean) {
            // Handle special timestamp marker
                return {"timestampValue": time:utcToString(time:utcNow())};
            }
            map<map<json>> convertedMap = {};
            foreach var [key, val] in value.entries() {
                convertedMap[key] = processFirestoreValue(val);
            }
            return {"mapValue": {"fields": convertedMap}};
        } else if value is json[] {
            json[] convertedArray = value.map(processFirestoreValue);
            return {"arrayValue": {"values": convertedArray}};
        } else {
            return {"stringValue": value.toJsonString()};
        }
}

public function extractFirestoreValue(json firestoreValue) returns json|error {
    if (!(firestoreValue is map<json>)) {
        return error("Invalid Firestore value format");
    }

    map<json> valueMap = <map<json>>firestoreValue;

    if valueMap.hasKey("stringValue") {
        return valueMap["stringValue"];
    } else if valueMap.hasKey("integerValue") {
        json integerValueJson = valueMap["integerValue"];
        if (integerValueJson is string) {
            return check int:fromString(integerValueJson);
        } else if (integerValueJson is int) {
            return integerValueJson;
        } else {
            return error("Invalid integer value format");
        }
    } else if valueMap.hasKey("booleanValue") {
        return valueMap["booleanValue"];
    } else if valueMap.hasKey("nullValue") {
        return null;
    } else if valueMap.hasKey("doubleValue") {
        json doubleValueJson = valueMap["doubleValue"];
        if (doubleValueJson is string) {
            return check float:fromString(doubleValueJson);
        } else if (doubleValueJson is float) {
            return doubleValueJson;
        } else {
            return error("Invalid double value format");
        }
    } else if valueMap.hasKey("timestampValue") {
        // Handle Firestore timestamp values
        json timestampValueJson = valueMap["timestampValue"];
        if (timestampValueJson is string) {
            // Return the ISO 8601 timestamp string as is
            // You can also convert it to a different format if needed
            return timestampValueJson;
        } else {
            return error("Invalid timestamp value format");
        }
    }
    else if valueMap.hasKey("mapValue") {
        map<json> result = {};
        json mapValueJson = valueMap["mapValue"];

        if (mapValueJson is map<json> && mapValueJson.hasKey("fields")) {
            map<json> fields = <map<json>>mapValueJson["fields"];

            foreach var [key, val] in fields.entries() {
                result[key] = check extractFirestoreValue(val);
            }
        }

        return result;
    } else if valueMap.hasKey("arrayValue") {
        json[] result = [];
        json arrayValueJson = valueMap["arrayValue"];

        if (arrayValueJson is map<json> && arrayValueJson.hasKey("values")) {
            json valuesJson = arrayValueJson["values"];
            if (valuesJson is json[]) {
                foreach var item in valuesJson {
                    result.push(check extractFirestoreValue(item));
                }
            }
        }

        return result;
    } else {
        log:printError("Unknown Firestore value type: " + firestoreValue.toJsonString());
        return "UNKNOWN_TYPE";
    }
}

public function buildFirestoreFilter(map<json> filter) returns json {
    if filter.length() == 0 {
        return {};
    }

    if filter.length() == 1 {
        string key = filter.keys()[0];
        json value = filter[key];

        return {
            "fieldFilter": {
                "field": {"fieldPath": key},
                "op": "EQUAL",
                "value": processFirestoreValue(value)
            }
        };
    }

    // For multiple conditions, create a composite filter
    json[] filters = [];

    foreach var [key, value] in filter.entries() {
        json singleFilter = {
            "fieldFilter": {
                "field": {"fieldPath": key},
                "op": "EQUAL",
                "value": processFirestoreValue(value)
            }
        };

        filters.push(singleFilter);
    }

    return {
        "compositeFilter": {
            "op": "AND",
            "filters": filters
        }
    };
}

public function queryFirestoreDocuments(
        string projectId,
        string accessToken,
        string collection,
        map<json> filter
) returns map<json>[]|error {
    string firestoreUrl = string `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`;

    http:Client firestoreClient = check new (firestoreUrl);
    http:Request request = new;

    request.setHeader("Authorization", string `Bearer ${accessToken}`);
    request.setHeader("Content-Type", "application/json");

    json whereFilter = buildFirestoreFilter(filter);

    json queryPayload = {
        "structuredQuery": {
            "from": [{"collectionId": collection}],
            "where": whereFilter
        }
    };

    request.setJsonPayload(queryPayload);

    http:Response response = check firestoreClient->post("", request);

    log:printInfo("Response status code: " + response.statusCode.toString());

    if (response.statusCode == 200) {
        json responsePayload = check response.getJsonPayload();

        // Handle both array and single object responses
        json[] responseArray = [];
        if (responsePayload is json[]) {
            responseArray = responsePayload;
        } else if (responsePayload is json) {
            // If it's a single object, wrap it in an array
            responseArray = [responsePayload];
        }
        map<json>[] results = [];

        log:printInfo("Processing " + responseArray.length().toString() + " documents");

        foreach json item in responseArray {
            // Check if the item has a document field
            if (item is map<json> && item.hasKey("document")) {
                map<json> documentWrapper = <map<json>>item["document"];

                if (documentWrapper.hasKey("fields")) {
                    map<json> document = {};
                    map<json> fields = <map<json>>documentWrapper["fields"];

                    // Extract each field
                    foreach var [key, value] in fields.entries() {
                        json|error extractedValue = extractFirestoreValue(value);
                        if (extractedValue is error) {
                            log:printError("Error extracting field " + key, extractedValue);
                            continue;
                        }
                        document[key] = extractedValue;
                    }

                    // Add the document ID from the name field
                    if (documentWrapper.hasKey("name")) {
                        string documentPath = <string>documentWrapper["name"];
                        string[] pathParts = regex:split(documentPath, "/");
                        document["id"] = pathParts[pathParts.length() - 1];
                    }

                    results.push(document);
                } else {
                    log:printError("Document does not have fields property");
                }
            } else {
                log:printError("Item does not have document property");
                log:printError("Item structure: " + item.toJsonString());
            }
        }

        log:printInfo("Successfully processed " + results.length().toString() + " documents");
        return results;

    } else {
        string errorBody = check response.getTextPayload();
        string errorMessage = "Failed to query documents. Status code: " + response.statusCode.toString() + " Error: " + errorBody;
        log:printError(errorMessage);
        return error(errorMessage);
    }
}


public function getFirestoreDocumentById(
    string projectId,
    string accessToken,
    string collection,
    string documentId
) returns map<json>|error {
    string firestoreUrl = string `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}/${documentId}`;
    
    http:Client firestoreClient = check new (firestoreUrl);
    map<string> headers = {
        "Authorization": string `Bearer ${accessToken}`,
        "Content-Type": "application/json"
    };
    
    http:Response response = check firestoreClient->get("", headers);
    
    log:printInfo("Response status code: " + response.statusCode.toString());
    
    if (response.statusCode == 200) {
        json responsePayload = check response.getJsonPayload();
        
        if (responsePayload is map<json> && responsePayload.hasKey("fields")) {
            map<json> document = {};
            map<json> fields = <map<json>>responsePayload["fields"];
            
            // Extract each field
            foreach var [key, value] in fields.entries() {
                json|error extractedValue = extractFirestoreValue(value);
                if (extractedValue is error) {
                    log:printError("Error extracting field " + key, extractedValue);
                    continue;
                }
                document[key] = extractedValue;
            }
            
            // Add the document ID
            document["id"] = documentId;
            
            log:printInfo("Successfully retrieved document with ID: " + documentId);
            return document;
        } else {
            string errorMessage = "Document does not have fields property";
            log:printError(errorMessage);
            return error(errorMessage);
        }
    } else if (response.statusCode == 404) {
        string errorMessage = "Document not found with ID: " + documentId;
        log:printError(errorMessage);
        return error(errorMessage);
    } else {
        string errorBody = check response.getTextPayload();
        string errorMessage = "Failed to get document. Status code: " + response.statusCode.toString() + " Error: " + errorBody;
        log:printError(errorMessage);
        return error(errorMessage);
    }
}
// Updated function that merges data instead of replacing
public function updateFirestoreDocument(
        string projectId,
        string accessToken,
        string collection,
        string documentId,
        map<json> documentData,
        string[]? updateMask = (),
        boolean merge = true  // New parameter to control merge behavior
) returns json|error {
    
    if merge && (updateMask is () || updateMask.length() == 0) {
        // If merge is true and no updateMask is provided, create one from the document data
        string[] autoUpdateMask = [];
        foreach var key in documentData.keys() {
            autoUpdateMask.push(key);
        }
        return updateFirestoreDocumentWithMask(projectId, accessToken, collection, documentId, documentData, autoUpdateMask);
    }
    
    return updateFirestoreDocumentWithMask(projectId, accessToken, collection, documentId, documentData, updateMask);
}

// Helper function that always uses updateMask
function updateFirestoreDocumentWithMask(
        string projectId,
        string accessToken,
        string collection,
        string documentId,
        map<json> documentData,
        string[]? updateMask
) returns json|error {
    string firestoreUrl = string `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${collection}/${documentId}`;

    // Add update mask to URL if provided
    if updateMask is string[] && updateMask.length() > 0 {
        string maskParams = "";
        foreach string fieldPath in updateMask {
            if maskParams == "" {
                maskParams = "?updateMask.fieldPaths=" + fieldPath;
            } else {
                maskParams = maskParams + "&updateMask.fieldPaths=" + fieldPath;
            }
        }
        firestoreUrl = firestoreUrl + maskParams;
    }

    http:Client firestoreClient = check new (firestoreUrl);
    http:Request request = new;

    request.setHeader("Authorization", string `Bearer ${accessToken}`);
    request.setHeader("Content-Type", "application/json");

    // Convert document data to Firestore format
    map<map<json>> firestoreFields = {};
    foreach var [key, value] in documentData.entries() {
        firestoreFields[key] = processFirestoreValue(value);
    }

    json payload = {
        fields: firestoreFields
    };

    request.setJsonPayload(payload);

    http:Response response = check firestoreClient->patch("", request);

    log:printInfo("Update response status code: " + response.statusCode.toString());

    if response.statusCode == 200 {
        json responsePayload = check response.getJsonPayload();
        log:printInfo("Document updated successfully");
        return responsePayload;
    } else {
        string errorBody = check response.getTextPayload();
        string errorMessage = "Failed to update document. Status code: " + response.statusCode.toString() + " Error: " + errorBody;
        log:printError(errorMessage);
        return error(errorMessage);
    }
}

// Function to replace entire document (equivalent to your current behavior)
public function replaceFirestoreDocument(
        string projectId,
        string accessToken,
        string collection,
        string documentId,
        map<json> documentData
) returns json|error {
    return updateFirestoreDocument(projectId, accessToken, collection, documentId, documentData, (), false);
}

// Function to merge specific fields (preserves existing data)
public function mergeFirestoreDocument(
        string projectId,
        string accessToken,
        string collection,
        string documentId,
        map<json> documentData
) returns json|error {
    return updateFirestoreDocument(projectId, accessToken, collection, documentId, documentData, (), true);
}

// Enhanced function for updating nested map fields
public function updateFirestoreNestedField(
        string projectId,
        string accessToken,
        string collection,
        string documentId,
        string fieldPath,
        json value
) returns json|error {
    map<json> updateData = {};
    updateData[fieldPath] = value;
    string[] updateMask = [fieldPath];
    
    return updateFirestoreDocument(projectId, accessToken, collection, documentId, updateData, updateMask, true);
}

// Function to update multiple specific fields
public function updateFirestoreFields(
        string projectId,
        string accessToken,
        string collection,
        string documentId,
        map<json> fieldsToUpdate
) returns json|error {
    string[] updateMask = [];
    foreach var key in fieldsToUpdate.keys() {
        updateMask.push(key);
    }
    
    return updateFirestoreDocument(projectId, accessToken, collection, documentId, fieldsToUpdate, updateMask, true);
}


//image

// const string FIREBASE_STORAGE_API = "carpooling-c6aa5.firebasestorage.app";
// const string FIREBASE_STORAGE_UPLOAD_API = "https://firebasestorage.googleapis.com/v0/b/";

// // Upload file to Firebase Storage
// public function uploadToStorage(string bucketName, string accessToken, string fileName, 
//                               byte[] fileData, string contentType) returns string|error {
    
//     http:Client storageClient = check new ("https://firebasestorage.googleapis.com");
    
//     string encodedFileName = check url:encode(fileName, "UTF-8");
//     // Construct upload URL
//     string uploadUrl = string `${bucketName}/o/${encodedFileName}`;
    
//     // Create request
//     http:Request req = new;
//     req.setHeader("Authorization", "Bearer " + accessToken);
//     req.setHeader("Content-Type", contentType);
//     req.setBinaryPayload(fileData);
    
//     // Make upload request
//     http:Response|error response = storageClient->post(uploadUrl, req);
    
//     if response is error {
//         log:printError("Storage upload request failed", response);
//         return error("Failed to upload to Firebase Storage: " + response.message());
//     }
    
//     if response.statusCode != 200 {
//         string|error errorBody = response.getTextPayload();
//         string errorMessage = errorBody is string ? errorBody : "Unknown error";
//         log:printError("Storage upload failed with status: " + response.statusCode.toString() + " - " + errorMessage);
//         return error("Upload failed: " + errorMessage);
//     }
    
//     json|error uploadResult = response.getJsonPayload();
//     if uploadResult is error {
//         log:printError("Failed to parse upload response", uploadResult);
//         return error("Failed to parse upload response");
//     }
    
//     log:printInfo("File uploaded successfully: " + fileName);
//     return fileName;
// }

// // Get download URL for uploaded file
// public function getDownloadUrl(string bucketName, string accessToken, string fileName) returns string|error {
    
//     http:Client storageClient = check new ("https://firebasestorage.googleapis.com");
    
//     // URL encode the file name
//     string encodedFileName = check url:encode(fileName, "UTF-8");
    
//     // Construct API URL
//     string apiUrl = string `/v0/b/${bucketName}/o/${encodedFileName}`;
    
//     // Create request
//     map<string> headers = {
//         "Authorization": "Bearer " + accessToken
//     };
    
//     // Make request to get file metadata
//     http:Response|error response = storageClient->get(apiUrl, headers);
    
//     if response is error {
//         log:printError("Failed to get file metadata", response);
//         return error("Failed to get file metadata: " + response.message());
//     }
    
//     if response.statusCode != 200 {
//         string|error errorBody = response.getTextPayload();
//         string errorMessage = errorBody is string ? errorBody : "Unknown error";
//         log:printError("Get metadata failed with status: " + response.statusCode.toString() + " - " + errorMessage);
//         return error("Failed to get file metadata: " + errorMessage);
//     }
    
//     json|error metadata = response.getJsonPayload();
//     if metadata is error {
//         log:printError("Failed to parse metadata response", metadata);
//         return error("Failed to parse metadata response");
//     }
    
//     // Extract download URL from metadata
//     json|error downloadTokens = metadata.downloadTokens;
//     if downloadTokens is error || downloadTokens is () {
//         log:printError("No download tokens found in metadata");
//         return error("No download tokens available for file");
//     }
    
//     // Construct download URL
//     string downloadUrl = string `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedFileName}?alt=media&token=${downloadTokens.toString()}`;
    
//     log:printInfo("Download URL generated for: " + fileName);
//     return downloadUrl;
// }

// // Alternative method to get download URL using Firebase REST API
// public function getDownloadUrlAlternative(string bucketName, string accessToken, string fileName) returns string|error {
    
//     http:Client storageClient = check new ("https://firebasestorage.googleapis.com");
    
//     // URL encode the file name
//     string encodedFileName = check url:encode(fileName, "UTF-8");
    
//     // Get file metadata first
//     string metadataUrl = string `/v0/b/${bucketName}/o/${encodedFileName}`;
    
//     map<string> headers = {
//         "Authorization": "Bearer " + accessToken
//     };
    
//     http:Response|error response = storageClient->get(metadataUrl, headers);
    
//     if response is error {
//         return error("Failed to get file metadata: " + response.message());
//     }
    
//     if response.statusCode != 200 {
//         return error("File not found or access denied");
//     }
    
//     json|error metadata = response.getJsonPayload();
//     if metadata is error {
//         return error("Failed to parse metadata");
//     }
    
//     // Check if file has public access or get signed URL
//     json|error mediaLink = metadata.mediaLink;
//     if mediaLink is string {
//         return mediaLink;
//     }
    
//     // Generate signed URL if needed
//     return generateSignedUrl(bucketName, accessToken, fileName);
// }

// // Generate signed URL for file access
// public function generateSignedUrl(string bucketName, string accessToken, string fileName) returns string|error {
    
//     // Calculate expiration time (1 hour from now)
//     time:Utc currentTime = time:utcNow();
//     time:Utc expirationTime = time:utcAddSeconds(currentTime, 3600); // 1 hour
    
//     // For production, you would need to implement proper signed URL generation
//     // This is a simplified version - in production, use Google Cloud Storage signed URLs
    
//     string encodedFileName = check url:encode(fileName, "UTF-8");
//     string downloadUrl = string `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedFileName}?alt=media`;
    
//     return downloadUrl;
// }

// // Delete file from Firebase Storage
// public function deleteFromStorage(string bucketName, string accessToken, string fileName) returns error? {
    
//     http:Client storageClient = check new ("https://firebasestorage.googleapis.com");
    
//     // URL encode the file name
//     string encodedFileName = check url:encode(fileName, "UTF-8");
    
//     // Construct delete URL
//     string deleteUrl = string `/v0/b/${bucketName}/o/${encodedFileName}`;
    
//     // Create request
//     http:Request req = new;
//     req.setHeader("Authorization", "Bearer " + accessToken);
    
//     // Make delete request
//     http:Response|error response = storageClient->delete(deleteUrl, req);
    
//     if response is error {
//         log:printError("Failed to delete file", response);
//         return error("Failed to delete file: " + response.message());
//     }
    
//     if response.statusCode != 204 && response.statusCode != 200 {
//         string|error errorBody = response.getTextPayload();
//         string errorMessage = errorBody is string ? errorBody : "Unknown error";
//         log:printError("Delete failed with status: " + response.statusCode.toString() + " - " + errorMessage);
//         return error("Failed to delete file: " + errorMessage);
//     }
    
//     log:printInfo("File deleted successfully: " + fileName);
// }

// // List files in Firebase Storage bucket
// public function listStorageFiles(string bucketName, string accessToken, string? prefix = ()) returns json|error {
    
//     http:Client storageClient = check new ("https://firebasestorage.googleapis.com");
    
//     // Construct list URL
//     string listUrl = string `/v0/b/${bucketName}/o`;
//     if prefix is string {
//         string encodedPrefix = check url:encode(prefix, "UTF-8");
//         listUrl = listUrl + "?prefix=" + encodedPrefix;
//     }
    
//     // Create request
//     map<string> headers = {
//         "Authorization": "Bearer " + accessToken
//     };
    
//     // Make list request
//     http:Response|error response = storageClient->get(listUrl, headers);
    
//     if response is error {
//         log:printError("Failed to list files", response);
//         return error("Failed to list files: " + response.message());
//     }
    
//     if response.statusCode != 200 {
//         string|error errorBody = response.getTextPayload();
//         string errorMessage = errorBody is string ? errorBody : "Unknown error";
//         log:printError("List files failed with status: " + response.statusCode.toString() + " - " + errorMessage);
//         return error("Failed to list files: " + errorMessage);
//     }
    
//     json|error fileList = response.getJsonPayload();
//     if fileList is error {
//         log:printError("Failed to parse file list response", fileList);
//         return error("Failed to parse file list response");
//     }
    
//     return fileList;
// }

// // Get file metadata
// public function getFileMetadata(string bucketName, string accessToken, string fileName) returns json|error {
    
//     http:Client storageClient = check new ("https://firebasestorage.googleapis.com");
    
//     // URL encode the file name
//     string encodedFileName = check url:encode(fileName, "UTF-8");
    
//     // Construct metadata URL
//     string metadataUrl = string `/v0/b/${bucketName}/o/${encodedFileName}`;
    
//     // Create request
//     map<string> headers = {
//         "Authorization": "Bearer " + accessToken
//     };
    
//     // Make request
//     http:Response|error response = storageClient->get(metadataUrl, headers);
    
//     if response is error {
//         log:printError("Failed to get file metadata", response);
//         return error("Failed to get file metadata: " + response.message());
//     }
    
//     if response.statusCode != 200 {
//         string|error errorBody = response.getTextPayload();
//         string errorMessage = errorBody is string ? errorBody : "Unknown error";
//         log:printError("Get metadata failed with status: " + response.statusCode.toString() + " - " + errorMessage);
//         return error("Failed to get file metadata: " + errorMessage);
//     }
    
//     json|error metadata = response.getJsonPayload();
//     if metadata is error {
//         log:printError("Failed to parse metadata response", metadata);
//         return error("Failed to parse metadata response");
//     }
    
//     return metadata;
// }

// // Helper function to validate file exists
// public function fileExists(string bucketName, string accessToken, string fileName) returns boolean {
//     json|error metadata = getFileMetadata(bucketName, accessToken, fileName);
//     return metadata is json;
// }

// // Helper function to get file size
// public function getFileSize(string bucketName, string accessToken, string fileName) returns int|error {
//     json|error metadata = getFileMetadata(bucketName, accessToken, fileName);
//     if metadata is error {
//         return metadata;
//     }
    
//     json|error sizeJson = metadata.size;
//     if sizeJson is error {
//         return error("File size not found in metadata");
//     }
    
//     string sizeStr = sizeJson.toString();
//     int|error size = int:fromString(sizeStr);
//     if size is error {
//         return error("Invalid file size format");
//     }
    
//     return size;
// }