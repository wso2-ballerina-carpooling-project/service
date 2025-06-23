import ballerina/http;
import ballerina/log;

import ballerina/regex;


import 'service.firebase_auth;
import ballerina/io;


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

    firebase_auth:Client authClient = check new(authConfig);
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
    
    http:Client firestoreClient = check new(firestoreUrl);
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

public function processFirestoreValue(json value) returns map<json> {
    if value is string {
        return {"stringValue": value};
    } else if value is int {
        return {"integerValue": value};
    } else if value is boolean {
        return {"booleanValue": value};
    } else if value is () {
        return {"nullValue": null};
    } else if value is map<json> {
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
    map<json> valueMap = <map<json>>firestoreValue;
    
    if valueMap.hasKey("stringValue") {
        return check valueMap.stringValue;
    } else if valueMap.hasKey("integerValue") {
        string integerValueStr = check valueMap.integerValue.ensureType();
        return check int:fromString(integerValueStr);
    } else if valueMap.hasKey("booleanValue") {
        return check valueMap.booleanValue;
    } else if valueMap.hasKey("nullValue") {
        return null;
    } else if valueMap.hasKey("doubleValue") {
        json doubleValueJson = check valueMap.doubleValue.ensureType();
        return check float:fromString(doubleValueJson.toString());
    } else if valueMap.hasKey("mapValue") {
        map<json> result = {};
        map<json> fields = check valueMap.mapValue.fields.ensureType();
        
        foreach var [key, val] in fields.entries() {
            result[key] = check extractFirestoreValue(val);
        }
        
        return result;
    } else if valueMap.hasKey("arrayValue") {
        json[] result = [];
        if check valueMap.values.ensureType() {
            json|error valuesResult = valueMap.arrayValue.values;
            if valuesResult is json {
                json[] values = <json[]>valuesResult;
            
            foreach var item in values {
                result.push(check extractFirestoreValue(item));
            }
        }
        
        return result;
    } else {
        return "UNKNOWN_TYPE";
    }
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
    
    http:Client firestoreClient = check new(firestoreUrl);
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

    io:print("resposnessee" , response.statusCode);
    
    if (response.statusCode == 200) {
        json[] responseArray = <json[]>check response.getJsonPayload();
        map<json>[] results = [];

        io:print(responseArray);
        
        foreach json item in responseArray {
            if (item.document is json) {
                map<json> document = {};
                map<json> fields = <map<json>> check item.document.fields;
                
                foreach var [key, value] in fields.entries() {
                    document[key] = check extractFirestoreValue(value);
                }
                
                // Add the document ID from the name field
                string documentPath = <string> check item.document.name;
                string[] pathParts = regex:split(documentPath, "/");
                document["id"] = pathParts[pathParts.length() - 1];
                
                results.push(document);
            }
        }
        
        io:print(results);
        return results;
    } else {
        string errorBody = check response.getTextPayload();
        log:printError("Error querying documents. Status code: " + response.statusCode.toString() + " Error details: " + errorBody);
        return error("Failed to query documents: " + errorBody);
    }
}




// public function main() returns error? {
//     common:GoogleCredentials credentials = {
//         serviceAccountJsonPath: "./service-account.json",
//         privateKeyFilePath: "./private.key",
//         tokenScope: "https://www.googleapis.com/auth/datastore"
//     };

//     string accessToken = check generateAccessToken(credentials);
//     io:println("Access Token: ", accessToken);

//     map<json> documentData = {
//         "name": "Nalaka Dinesh",
//         "age": 30,
//         "active": true
//     };

//     check createFirestoreDocument(
//         "carpooling-c6aa5", 
//         accessToken, 
//         "users", 
//         documentData
//     );
// }
