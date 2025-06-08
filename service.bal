import 'service.Map;
import 'service.auth;
import 'service.firebase;
import ballerina/http;
import ballerina/io;
import ballerina/websocket;
import ballerina/time;
import ballerina/log;
import 'service.common;


configurable int wsport = ?;
configurable string host = ?;
map<websocket:Caller> connectedDrivers = {};
map<common:DriverInfo> driverInfoMap = {};



type PlaceInfo record {
    string description;
    string place_id;
};



function createSuccessResponse(int statusCode, json payload) returns http:Response {
    http:Response response = new;
    response.statusCode = statusCode;
    response.setJsonPayload(payload);
    return response;
}

// Helper function to create an error response
function createErrorResponse(int statusCode, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = statusCode;
    response.setJsonPayload({
        "status": "ERROR",
        "message": message
    });
    return response;
}

service /api on new http:Listener(9090) {
    resource function post register(@http:Payload json payload) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = auth:register(payload, accessToken);
        return response;
    }

    resource function post login(@http:Payload json payload) returns http:Response|error {
        string accessToken = checkpanic firebase:generateAccessToken();
        http:Response|error response = auth:login(payload, accessToken);
        return response;

    }

    resource function get direction() {
        error? response = Map:getDirection();
    }

     resource function post searchLocation(@http:Payload json payload) returns http:Response|error {
        // Safely extract the 'text' field from the payload
        string searchQuery = check payload.text.ensureType();
        io:println("Searching for places matching: '" + searchQuery + "'");

        // Call the function that uses Google Places API
        http:Response|error results = Map:searchSriLankaPlaces(searchQuery);
        return results;
    }

    // resource function get test() {
    //     string token = checkpanic auth:generateLoginToken().ensureType();
    //     io:println(token);
    //     jwt:Payload|error payload = auth:verifyToken(token);
    //     io:println(payload);
    // }

}

//websocket
service /ws on new websocket:Listener(wsport) {

    // Resource for handling new WebSocket connections
    resource function get .() returns websocket:Service|websocket:UpgradeError {
        log:printInfo("New WebSocket connection request received");
        return new LocationWebSocketService();
    }
}


isolated service class LocationWebSocketService {
    *websocket:Service;
    
    // Called when a new connection is established
    remote function onOpen(websocket:Caller caller) returns websocket:Error? {
        log:printInfo("WebSocket connection opened");
        
        // Send welcome message to the client
        json welcomeMessage = {
            "type": "connection_established",
            "message": "Welcome to the location tracking service",
            "timestamp": time:utcNow()
        };
        
        check caller->writeMessage(welcomeMessage);
    }

    // Called when a message is received from the client
    remote function onMessage(websocket:Caller caller, string|json|byte[]|xml message) returns websocket:Error? {
        
        if message is string {
            log:printInfo("Received text message from client");
            json|error jsonMessage = message.fromJsonString();
            
            if jsonMessage is json {
                check handleJsonMessage(caller, jsonMessage);
            } else {
                log:printError("Failed to parse JSON message", jsonMessage);
                check sendErrorResponse(caller, "Invalid JSON format");
            }
        } else if message is json {
            log:printInfo("Received JSON message from client");
            check handleJsonMessage(caller, message);
        } else {
            log:printWarn("Received unsupported message type");
            check sendErrorResponse(caller, "Unsupported message type");
        }
    }

    // Called when the WebSocket connection is closed
    remote function onClose(websocket:Caller caller, int statusCode, string reason) {
        log:printInfo(string `WebSocket connection closed. Status: ${statusCode}, Reason: ${reason}`);
        
        // Remove the driver from connected drivers map
        lock {
            string? driverIdToRemove = ();
            foreach var [key, value] in connectedDrivers.entries() {
                if value === caller {
                    driverIdToRemove = key;
                    break;
                }
            }
            
            if driverIdToRemove is string {
                _ = connectedDrivers.remove(driverIdToRemove);
                _ = driverInfoMap.remove(driverIdToRemove);
                log:printInfo("Driver removed from connected drivers: " + driverIdToRemove);
            }
        }
    }

    // Called when an error occurs
    remote function onError(websocket:Caller caller, websocket:Error err) {
        log:printError("WebSocket error occurred", err);
    }
}

// Handle JSON message based on type
function handleJsonMessage(websocket:Caller caller, json message) returns websocket:Error? {
    var messageType = message.'type;
    
    if messageType is string {
        match messageType {
            "driver_connected" => {
                check handleDriverConnected(caller, message);
            }
            "location_update" => {
                check handleLocationUpdate(caller, message);
            }
            "heartbeat" => {
                check handleHeartbeat(caller, message);
            }
            "waypoint_approaching" => {
                check handleWaypointApproaching(caller, message);
            }
            "pickup_arrival" => {
                check handlePickupArrival(caller, message);
            }
            "passenger_picked_up" => {
                check handlePassengerPickedUp(caller, message);
            }
            "driver_disconnected" => {
                check handleDriverDisconnected(caller, message);
            }
            _ => {
                log:printWarn("Unknown message type received: " + messageType);
                check sendErrorResponse(caller, "Unknown message type");
            }
        }
    } else {
        log:printError("Invalid message format - missing type field");
        check sendErrorResponse(caller, "Invalid message format");
    }
}

// Handle driver connection
function handleDriverConnected(websocket:Caller caller, json message) returns websocket:Error? {
    common:DriverConnectedMessage|error parseResult = message.cloneWithType();
    
    if parseResult is common:DriverConnectedMessage {
        string driverId = parseResult.driver_id;
        string rideId = parseResult.ride_id;
        
        // Store the driver connection
        lock {
            connectedDrivers[driverId] = caller;
            driverInfoMap[driverId] = {
                driverId: driverId,
                rideId: rideId,
                connectionTime: parseResult.timestamp,
                lastLatitude: 0,
                lastLocationUpdate: "",
                lastLongitude: 0
            };
        }
        
        // Console log
        io:println("=== DRIVER CONNECTED ===");
        io:println("Driver ID: " + driverId);
        io:println("Ride ID: " + rideId);
        io:println("Connection Time: " + parseResult.timestamp);
        io:println("Total Connected Drivers: " + connectedDrivers.length().toString());
        io:println("========================");
        
        // Send acknowledgment
        json response = {
            "type": "driver_connected_ack",
            "driver_id": driverId,
            "status": "success",
            "timestamp": time:utcNow()
        };
        
        check caller->writeMessage(response);
    } else {
        log:printError("Invalid driver connected message format", parseResult);
        check sendErrorResponse(caller, "Invalid driver connected message format");
    }
}

// Handle location update
function handleLocationUpdate(websocket:Caller caller, json message) returns websocket:Error? {
    common:LocationUpdateMessage|error parseResult = message.cloneWithType();
    
    if parseResult is common:LocationUpdateMessage {
        string driverId = parseResult.driver_id;
        string rideId = parseResult.ride_id;
        decimal latitude = parseResult.latitude;
        decimal longitude = parseResult.longitude;
        
        // Update driver info with latest location
        lock {
            if driverInfoMap.hasKey(driverId) {
                common:DriverInfo driverInfo = driverInfoMap.get(driverId);
                driverInfo.lastLatitude = latitude;
                driverInfo.lastLongitude = longitude;
                driverInfo.lastLocationUpdate = parseResult.timestamp;
                driverInfoMap[driverId] = driverInfo;
            }
        }
        
        // Console log
        io:println("=== LOCATION UPDATE ===");
        io:println("Driver ID: " + driverId);
        io:println("Ride ID: " + rideId);
        io:println("Latitude: " + latitude.toString());
        io:println("Longitude: " + longitude.toString());
        
        if parseResult.speed is decimal {
            io:println("Speed: " + parseResult.speed.toString() + " m/s");
        }
        
        if parseResult.heading is decimal {
            io:println("Heading: " + parseResult.heading.toString() + "°");
        }
        
        if parseResult.accuracy is decimal {
            io:println("Accuracy: " + parseResult.accuracy.toString() + " meters");
        }
        
        io:println("Timestamp: " + parseResult.timestamp);
        io:println("======================");
        
        // Send acknowledgment
        json response = {
            "type": "location_received",
            "driver_id": driverId,
            "status": "success",
            "timestamp": time:utcNow()
        };
        
        check caller->writeMessage(response);
    } else {
        log:printError("Invalid location update message format", parseResult);
        check sendErrorResponse(caller, "Invalid location update message format");
    }
}

// Handle heartbeat
function handleHeartbeat(websocket:Caller caller, json message) returns websocket:Error? {
    common:HeartbeatMessage|error parseResult = message.cloneWithType();
    
    if parseResult is common:HeartbeatMessage {
        string driverId = parseResult.driver_id;
        
        // Console log (can be made less verbose if needed)
        io:println("=== HEARTBEAT ===");
        io:println("Driver ID: " + driverId);
        io:println("Timestamp: " + parseResult.timestamp);
        io:println("=================");
        
        // Send heartbeat response
        json response = {
            "type": "heartbeat_ack",
            "driver_id": driverId,
            "server_timestamp": time:utcNow()
        };
        
        check caller->writeMessage(response);
    } else {
        log:printError("Invalid heartbeat message format", parseResult);
        check sendErrorResponse(caller, "Invalid heartbeat message format");
    }
}

// Handle waypoint approaching
function handleWaypointApproaching(websocket:Caller caller, json message) returns websocket:Error? {
    common:WaypointApproachingMessage|error parseResult = message.cloneWithType();
    
    if parseResult is common:WaypointApproachingMessage {
        string driverId = parseResult.driver_id;
        string rideId = parseResult.ride_id;
        
        // Console log
        io:println("=== WAYPOINT APPROACHING ===");
        io:println("Driver ID: " + driverId);
        io:println("Ride ID: " + rideId);
        io:println("Waypoint Latitude: " + parseResult.waypoint_latitude.toString());
        io:println("Waypoint Longitude: " + parseResult.waypoint_longitude.toString());
        io:println("Distance to Waypoint: " + parseResult.distance_to_waypoint.toString() + " meters");
        io:println("Timestamp: " + parseResult.timestamp);
        io:println("============================");
        
        // Send acknowledgment
        json response = {
            "type": "waypoint_approaching_ack",
            "driver_id": driverId,
            "status": "received",
            "timestamp": time:utcNow()
        };
        
        check caller->writeMessage(response);
    } else {
        log:printError("Invalid waypoint approaching message format", parseResult);
        check sendErrorResponse(caller, "Invalid waypoint approaching message format");
    }
}

// Handle pickup arrival
function handlePickupArrival(websocket:Caller caller, json message) returns websocket:Error? {
    common:PickupArrivalMessage|error parseResult = message.cloneWithType();
    
    if parseResult is common:PickupArrivalMessage {
        string driverId = parseResult.driver_id;
        string rideId = parseResult.ride_id;
        string passengerName = parseResult.passenger_name;
        
        // Console log
        io:println("=== PICKUP ARRIVAL ===");
        io:println("Driver ID: " + driverId);
        io:println("Ride ID: " + rideId);
        io:println("Passenger Name: " + passengerName);
        io:println("Timestamp: " + parseResult.timestamp);
        io:println("======================");
        
        // Send acknowledgment
        json response = {
            "type": "pickup_arrival_ack",
            "driver_id": driverId,
            "status": "received",
            "timestamp": time:utcNow()
        };
        
        check caller->writeMessage(response);
    } else {
        log:printError("Invalid pickup arrival message format", parseResult);
        check sendErrorResponse(caller, "Invalid pickup arrival message format");
    }
}

// Handle passenger picked up
function handlePassengerPickedUp(websocket:Caller caller, json message) returns websocket:Error? {
    common:PassengerPickedUpMessage|error parseResult = message.cloneWithType();
    
    if parseResult is common:PassengerPickedUpMessage {
        string driverId = parseResult.driver_id;
        string rideId = parseResult.ride_id;
        string passengerName = parseResult.passenger_name;
        
        // Console log
        io:println("=== PASSENGER PICKED UP ===");
        io:println("Driver ID: " + driverId);
        io:println("Ride ID: " + rideId);
        io:println("Passenger Name: " + passengerName);
        io:println("Timestamp: " + parseResult.timestamp);
        io:println("===========================");
        
        // Send acknowledgment
        json response = {
            "type": "passenger_picked_up_ack",
            "driver_id": driverId,
            "status": "received",
            "timestamp": time:utcNow()
        };
        
        check caller->writeMessage(response);
    } else {
        log:printError("Invalid passenger picked up message format", parseResult);
        check sendErrorResponse(caller, "Invalid passenger picked up message format");
    }
}

// Handle driver disconnection
function handleDriverDisconnected(websocket:Caller caller, json message) returns websocket:Error? {
    common:DriverDisconnectedMessage|error parseResult = message.cloneWithType();
    
    if parseResult is common:DriverDisconnectedMessage {
        string driverId = parseResult.driver_id;
        string rideId = parseResult.ride_id;
        
        // Console log
        io:println("=== DRIVER DISCONNECTED ===");
        io:println("Driver ID: " + driverId);
        io:println("Ride ID: " + rideId);
        io:println("Timestamp: " + parseResult.timestamp);
        io:println("===========================");
        
        // Remove from connected drivers
        lock {
            _ = connectedDrivers.remove(driverId);
            _ = driverInfoMap.remove(driverId);
        }
        
        io:println("Remaining Connected Drivers: " + connectedDrivers.length().toString());
    } else {
        log:printError("Invalid driver disconnected message format", parseResult);
    }
}

// Send error response to client
function sendErrorResponse(websocket:Caller caller, string errorMessage) returns websocket:Error? {
    json errorResponse = {
        "type": "error",
        "message": errorMessage,
        "timestamp": time:utcNow()
    };
    
    check caller->writeMessage(errorResponse);
}

// Utility function to get current driver status
function getCurrentDriverStatus() {
    io:println("=== CURRENT DRIVER STATUS ===");
    lock {
        if connectedDrivers.length() == 0 {
            io:println("No drivers currently connected");
        } else {
            io:println("Connected Drivers: " + connectedDrivers.length().toString());
            
            foreach var [driverId, driverInfo] in driverInfoMap.entries() {
                io:println("Driver ID: " + driverId);
                io:println("Ride ID: " + driverInfo.rideId);
                io:println("Connection Time: " + driverInfo.connectionTime);
                
                if driverInfo.lastLatitude is decimal && driverInfo.lastLongitude is decimal {
                    io:println("Last Location: " + driverInfo.lastLatitude.toString() + ", " + driverInfo.lastLongitude.toString());
                }
                
                if driverInfo.lastLocationUpdate is string {
                    io:println( driverInfo.lastLocationUpdate);
                }
                
                io:println("---");
            }
        }
    }
    io:println("=============================");
}

// Function to broadcast message to all connected drivers (utility function)
function broadcastToAllDrivers(json message) returns websocket:Error? {
    lock {
        foreach var [driverId, caller] in connectedDrivers.entries() {
            websocket:Error? result = caller->writeMessage(message);
            if result is websocket:Error {
                log:printError("Error broadcasting message to driver: " + driverId, result);
            }
        }
    }
}

// Main function to start the service
public function main() returns error? {
    io:println("=== LOCATION TRACKING WEBSOCKET SERVICE ===");
    io:println("Starting WebSocket service on " + host + ":" + wsport.toString());
    io:println("WebSocket endpoint: ws://" + host + ":" + wsport.toString() + "/ws");
    io:println("==========================================");
    
    // The service will automatically start when the application runs
    // You can add any additional initialization logic here
    
    // Optional: Print status every 60 seconds
    // Note: Removed periodic status check as runtime:sleep is deprecated
    // You can implement this using scheduled tasks if needed
    
    getCurrentDriverStatus();
}




// import ballerina/http;
// import ballerina/log;
// import server.auth;
// // Protected API endpoint example
// service /api/v1 on new http:Listener(8080) {

//     // Public endpoint - login
//     resource function post login(@http:Payload json payload) returns http:Response|error {
//         string? email = check payload.email.ensureType();
//         string? password = check payload.password.ensureType();

//         if email is () || password is () {
//             return createErrorResponse(400, "Email and password are required");
//         }

//         // Here you would validate credentials from your database
//         // For this example, assume we found the user
//         string userId = "user123";
//         string role = "driver";

//         // Generate JWT token
//         string|error token = auth:generateJwtToken(userId, <string>email, role);

//         if token is error {
//             log:printError("Failed to generate token", token);
//             return createErrorResponse(500, "Authentication failed");
//         }

//         // Return token to client
//         return createSuccessResponse(200, {
//             "userId": userId,
//             "email": email,
//             "role": role,
//             "token": token
//         });
//     }

//     // Protected endpoint - requires authentication
//     resource function get profile(http:Request request) returns http:Response|error {
//         // Validate JWT token
//         boolean|error validation = auth:validateRequestToken(request);

//         if validation is error {
//             return createErrorResponse(401, validation.message());
//         }

//         boolean isValid = validation;

//         if !isValid {
//             return createErrorResponse(401, "Invalid authentication token");
//         }

//         // Here you would fetch the user's profile from your database
//         // For this example, we'll just return the information from the token
//         return createSuccessResponse(200, {
//             "profileComplete": true
//         });
//     }

//     // Protected endpoint with role check

// }

// // Helper functions for creating responses
// function createSuccessResponse(int statusCode, json data) returns http:Response {
//     http:Response response = new;
//     response.statusCode = statusCode;
//     response.setJsonPayload(data);
//     return response;
// }

// function createErrorResponse(int statusCode, string message) returns http:Response {
//     http:Response response = new;
//     response.statusCode = statusCode;
//     response.setJsonPayload({"error": message});
//     return response;
// }



