import ballerina/http;
import ballerina/io;
import ballerina/url;
import 'service.utility as utility;
// import ballerina/log;

// Configuration for Google Maps Directions API
 // Replace with your Google Maps API key

configurable string dirApiKey = ?;
configurable string placeApiKey = ?;

type PlaceInfo record {
    string description;
    string place_id;
};


public function getDirection(http:Request req) returns http:Response|error {
    http:Client directionsClient = check new ("https://maps.googleapis.com");
    json|error payload = req.getJsonPayload();

    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    string origin = check payload.origin;
    string destination = check payload.destination;
    string[] travelModes = ["driving"];
    
    foreach string mode in travelModes {
        io:println("\n=== Routes for " + mode + " mode ===");
        
        // Encode parameters to ensure they're URL-safe
        string encodedOrigin = check url:encode(origin, "UTF-8");
        string encodedDestination = check url:encode(destination, "UTF-8");
        
        string path = string `/maps/api/directions/json?origin=${encodedOrigin}&destination=${encodedDestination}&mode=${mode}&alternatives=true&key=${dirApiKey}`;
        
        json response = check directionsClient->get(path);
        
        io:println(response);

        return utility:createSuccessResponse(200,response);
    }
    return utility:createErrorResponse(404,"No matching rides");
}

function processRoutes(json response) {
    // Extract status from response
    string|error status = response.status.ensureType();
    
    if status != "OK" {
        // io:println(status);
        return;
    }
    
    // Extract routes from response
    json[] routes = <json[]> checkpanic response.routes.ensureType();
    int routeCount = routes.length();

    io:println(routes[0]);
    
    io:println(string `Found ${routeCount} route(s)`);
    
    // Process each route
    foreach int i in 0 ..< routeCount {
        json route = routes[i];
        
        // Get summary of the route
        string summary = checkpanic route.summary.ensureType();
        
        // Get duration and distance
        json[] legs = <json[]> checkpanic route.legs.ensureType();
        json legsData = legs[0];
        string duration =  checkpanic legsData.duration.text.ensureType();
        string distance =  checkpanic legsData.distance.text.ensureType();
        
        io:println(string `Route ${i + 1}: ${summary}`);
        io:println(string `  Distance: ${distance}`);
        io:println(string `  Duration: ${duration}`);
        
        // Get steps for detailed navigation (optional)
        io:println("  Steps:");
        json[] steps = <json[]> checkpanic legsData.steps.ensureType();
        foreach json step in steps {
            string instruction = checkpanic step.html_instructions.ensureType();
            // Remove HTML tags for cleaner output
            instruction = removeHtmlTags(instruction);
            string stepDistance = checkpanic step.distance.text.ensureType();
            io:println(string `    - ${instruction} (${stepDistance})`);
        }
    }
}

// Helper function to remove HTML tags from instructions
function removeHtmlTags(string htmlText) returns string {
    string result = "";
    boolean insideTag = false;
    
    foreach var char in htmlText {
        if char == "<" {
            insideTag = true;
            continue;
        }
        
        if char == ">" {
            insideTag = false;
            result += " ";
            continue;
        }
        
        if !insideTag {
            result += char;
        }
    }
    
    return result;
}

public function searchSriLankaPlaces(string query) returns http:Response|error {

    http:ClientConfiguration clientConfig = {
        timeout: 30,
        retryConfig: {
            count: 2,
            interval: 1,
            backOffFactor: 2.0,
            maxWaitInterval: 20
        }
    };
    
    http:Client httpClient = check new ("https://places.googleapis.com", clientConfig);
    
    string path = "/v1/places:searchText";
    
    json requestPayload = {
        "textQuery": query,
        "locationRestriction": {
            "rectangle": {
                "low": {
                    "latitude": 5.9, // Southern boundary of Sri Lanka
                    "longitude": 79.5 // Western boundary of Sri Lanka
                },
                "high": {
                    "latitude": 9.9, // Northern boundary of Sri Lanka
                    "longitude": 81.9 // Eastern boundary of Sri Lanka
                }
            }
        }
    };
    
    // Prepare headers
    map<string> headers = {
        "X-Goog-Api-Key": placeApiKey,
        "X-Goog-FieldMask": "places.displayName,places.id"
    };
    
    // Send the POST request
    io:println("Sending request to: " + path);
    http:Response response = check httpClient->post(path, requestPayload, headers);
    return response;
    
    // Process the response
    // if (response.statusCode == 200) {
    //     json payload = check response.getJsonPayload();
    //     io:println("Response: " + payload.toString());
        
    //     PlaceInfo[] results = [];
        
    //     // Check if places exist in the response
    //     if payload.places is json[] {
    //         json[] places = <json[]> check payload.places.ensureType();
            
    //         foreach json place in places {
    //             PlaceInfo placeInfo = {
    //                 description: check place.displayName.text.ensureType(),
    //                 place_id: check place.id.ensureType()
    //             };
    //             results.push(placeInfo);
    //         }
    //     }
        
    //     return results;
    // } else {
    //     string errorBody = check response.getTextPayload();
    //     log:printError("API returned error status: " + response.statusCode.toString());
    //     log:printError("Error details: " + errorBody);
    // }
    
    // // Return empty array if request fails
    // return [];
}

