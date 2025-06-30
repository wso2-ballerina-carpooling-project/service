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