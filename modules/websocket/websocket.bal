
// import ballerina/websocket;
// import ballerina/io;
// import ballerina/log;
// import ballerina/time;
// import 'service.common;

// Configuration for the WebSocket service
// configurable int port = 9090;
// configurable string host = "0.0.0.0";

// // Store connected clients with their driver information
// map<websocket:Caller> connectedDrivers = {};
// map<common:DriverInfo> driverInfoMap = {};

// configurable int port = ?;
// configurable string host = ?;

// // Driver information structure
// type DriverInfo record {
//     string driverId;
//     string rideId;
//     string connectionTime;
//     decimal? lastLatitude;
//     decimal? lastLongitude;
//     string? lastLocationUpdate;
// };

// // Message types from Flutter app
// type LocationUpdateMessage record {
//     string 'type;
//     string driver_id;
//     string ride_id;
//     decimal latitude;
//     decimal longitude;
//     decimal speed?;
//     decimal heading?;
//     string timestamp;
//     decimal accuracy?;
// };

// type DriverConnectedMessage record {
//     string 'type;
//     string driver_id;
//     string ride_id;
//     string timestamp;
// };

// type DriverDisconnectedMessage record {
//     string 'type;
//     string driver_id;
//     string ride_id;
//     string timestamp;
// };

// type HeartbeatMessage record {
//     string 'type;
//     string driver_id;
//     string timestamp;
// };

// type WaypointApproachingMessage record {
//     string 'type;
//     string driver_id;
//     string ride_id;
//     decimal waypoint_latitude;
//     decimal waypoint_longitude;
//     decimal distance_to_waypoint;
//     string timestamp;
// };

// type PickupArrivalMessage record {
//     string 'type;
//     string driver_id;
//     string ride_id;
//     string passenger_name;
//     string timestamp;
// };

// type PassengerPickedUpMessage record {
//     string 'type;
//     string driver_id;
//     string ride_id;
//     string passenger_name;
//     string timestamp;
// };

// WebSocket service
// service /ws on new websocket:Listener(port) {

//     // Resource for handling new WebSocket connections
//     resource function get .() returns websocket:Service|websocket:UpgradeError {
//         log:printInfo("New WebSocket connection request received");
//         return new LocationWebSocketService();
//     }
// }

// WebSocket service implementation
// isolated service class LocationWebSocketService {
//     *websocket:Service;
    
//     // Called when a new connection is established
//     remote function onOpen(websocket:Caller caller) returns websocket:Error? {
//         log:printInfo("WebSocket connection opened");
        
//         // Send welcome message to the client
//         json welcomeMessage = {
//             "type": "connection_established",
//             "message": "Welcome to the location tracking service",
//             "timestamp": time:utcNow()
//         };
        
//         check caller->writeMessage(welcomeMessage);
//     }

//     // Called when a message is received from the client
//     remote function onMessage(websocket:Caller caller, string|json|byte[]|xml message) returns websocket:Error? {
        
//         if message is string {
//             log:printInfo("Received text message from client");
//             json|error jsonMessage = message.fromJsonString();
            
//             if jsonMessage is json {
//                 check handleJsonMessage(caller, jsonMessage);
//             } else {
//                 log:printError("Failed to parse JSON message", jsonMessage);
//                 check sendErrorResponse(caller, "Invalid JSON format");
//             }
//         } else if message is json {
//             log:printInfo("Received JSON message from client");
//             check handleJsonMessage(caller, message);
//         } else {
//             log:printWarn("Received unsupported message type");
//             check sendErrorResponse(caller, "Unsupported message type");
//         }
//     }

//     // Called when the WebSocket connection is closed
//     remote function onClose(websocket:Caller caller, int statusCode, string reason) {
//         log:printInfo(string `WebSocket connection closed. Status: ${statusCode}, Reason: ${reason}`);
        
//         // Remove the driver from connected drivers map
//         lock {
//             string? driverIdToRemove = ();
//             foreach var [key, value] in connectedDrivers.entries() {
//                 if value === caller {
//                     driverIdToRemove = key;
//                     break;
//                 }
//             }
            
//             if driverIdToRemove is string {
//                 _ = connectedDrivers.remove(driverIdToRemove);
//                 _ = driverInfoMap.remove(driverIdToRemove);
//                 log:printInfo("Driver removed from connected drivers: " + driverIdToRemove);
//             }
//         }
//     }

//     // Called when an error occurs
//     remote function onError(websocket:Caller caller, websocket:Error err) {
//         log:printError("WebSocket error occurred", err);
//     }
// }

// // Handle JSON message based on type
// function handleJsonMessage(websocket:Caller caller, json message) returns websocket:Error? {
//     var messageType = message.'type;
    
//     if messageType is string {
//         match messageType {
//             "driver_connected" => {
//                 check handleDriverConnected(caller, message);
//             }
//             "location_update" => {
//                 check handleLocationUpdate(caller, message);
//             }
//             "heartbeat" => {
//                 check handleHeartbeat(caller, message);
//             }
//             "waypoint_approaching" => {
//                 check handleWaypointApproaching(caller, message);
//             }
//             "pickup_arrival" => {
//                 check handlePickupArrival(caller, message);
//             }
//             "passenger_picked_up" => {
//                 check handlePassengerPickedUp(caller, message);
//             }
//             "driver_disconnected" => {
//                 check handleDriverDisconnected(caller, message);
//             }
//             _ => {
//                 log:printWarn("Unknown message type received: " + messageType);
//                 check sendErrorResponse(caller, "Unknown message type");
//             }
//         }
//     } else {
//         log:printError("Invalid message format - missing type field");
//         check sendErrorResponse(caller, "Invalid message format");
//     }
// }

// // Handle driver connection
// function handleDriverConnected(websocket:Caller caller, json message) returns websocket:Error? {
//     common:DriverConnectedMessage|error parseResult = message.cloneWithType();
    
//     if parseResult is common:DriverConnectedMessage {
//         string driverId = parseResult.driver_id;
//         string rideId = parseResult.ride_id;
        
//         // Store the driver connection
//         lock {
//             connectedDrivers[driverId] = caller;
//             driverInfoMap[driverId] = {
//                 driverId: driverId,
//                 rideId: rideId,
//                 connectionTime: parseResult.timestamp,
//                 lastLatitude: 0,
//                 lastLocationUpdate: "",
//                 lastLongitude: 0
//             };
//         }
        
//         // Console log
//         io:println("=== DRIVER CONNECTED ===");
//         io:println("Driver ID: " + driverId);
//         io:println("Ride ID: " + rideId);
//         io:println("Connection Time: " + parseResult.timestamp);
//         io:println("Total Connected Drivers: " + connectedDrivers.length().toString());
//         io:println("========================");
        
//         // Send acknowledgment
//         json response = {
//             "type": "driver_connected_ack",
//             "driver_id": driverId,
//             "status": "success",
//             "timestamp": time:utcNow()
//         };
        
//         check caller->writeMessage(response);
//     } else {
//         log:printError("Invalid driver connected message format", parseResult);
//         check sendErrorResponse(caller, "Invalid driver connected message format");
//     }
// }

// // Handle location update
// function handleLocationUpdate(websocket:Caller caller, json message) returns websocket:Error? {
//     common:LocationUpdateMessage|error parseResult = message.cloneWithType();
    
//     if parseResult is common:LocationUpdateMessage {
//         string driverId = parseResult.driver_id;
//         string rideId = parseResult.ride_id;
//         decimal latitude = parseResult.latitude;
//         decimal longitude = parseResult.longitude;
        
//         // Update driver info with latest location
//         lock {
//             if driverInfoMap.hasKey(driverId) {
//                 common:DriverInfo driverInfo = driverInfoMap.get(driverId);
//                 driverInfo.lastLatitude = latitude;
//                 driverInfo.lastLongitude = longitude;
//                 driverInfo.lastLocationUpdate = parseResult.timestamp;
//                 driverInfoMap[driverId] = driverInfo;
//             }
//         }
        
//         // Console log
//         io:println("=== LOCATION UPDATE ===");
//         io:println("Driver ID: " + driverId);
//         io:println("Ride ID: " + rideId);
//         io:println("Latitude: " + latitude.toString());
//         io:println("Longitude: " + longitude.toString());
        
//         if parseResult.speed is decimal {
//             io:println("Speed: " + parseResult.speed.toString() + " m/s");
//         }
        
//         if parseResult.heading is decimal {
//             io:println("Heading: " + parseResult.heading.toString() + "°");
//         }
        
//         if parseResult.accuracy is decimal {
//             io:println("Accuracy: " + parseResult.accuracy.toString() + " meters");
//         }
        
//         io:println("Timestamp: " + parseResult.timestamp);
//         io:println("======================");
        
//         // Send acknowledgment
//         json response = {
//             "type": "location_received",
//             "driver_id": driverId,
//             "status": "success",
//             "timestamp": time:utcNow()
//         };
        
//         check caller->writeMessage(response);
//     } else {
//         log:printError("Invalid location update message format", parseResult);
//         check sendErrorResponse(caller, "Invalid location update message format");
//     }
// }

// // Handle heartbeat
// function handleHeartbeat(websocket:Caller caller, json message) returns websocket:Error? {
//     common:HeartbeatMessage|error parseResult = message.cloneWithType();
    
//     if parseResult is common:HeartbeatMessage {
//         string driverId = parseResult.driver_id;
        
//         // Console log (can be made less verbose if needed)
//         io:println("=== HEARTBEAT ===");
//         io:println("Driver ID: " + driverId);
//         io:println("Timestamp: " + parseResult.timestamp);
//         io:println("=================");
        
//         // Send heartbeat response
//         json response = {
//             "type": "heartbeat_ack",
//             "driver_id": driverId,
//             "server_timestamp": time:utcNow()
//         };
        
//         check caller->writeMessage(response);
//     } else {
//         log:printError("Invalid heartbeat message format", parseResult);
//         check sendErrorResponse(caller, "Invalid heartbeat message format");
//     }
// }

// // Handle waypoint approaching
// function handleWaypointApproaching(websocket:Caller caller, json message) returns websocket:Error? {
//     common:WaypointApproachingMessage|error parseResult = message.cloneWithType();
    
//     if parseResult is common:WaypointApproachingMessage {
//         string driverId = parseResult.driver_id;
//         string rideId = parseResult.ride_id;
        
//         // Console log
//         io:println("=== WAYPOINT APPROACHING ===");
//         io:println("Driver ID: " + driverId);
//         io:println("Ride ID: " + rideId);
//         io:println("Waypoint Latitude: " + parseResult.waypoint_latitude.toString());
//         io:println("Waypoint Longitude: " + parseResult.waypoint_longitude.toString());
//         io:println("Distance to Waypoint: " + parseResult.distance_to_waypoint.toString() + " meters");
//         io:println("Timestamp: " + parseResult.timestamp);
//         io:println("============================");
        
//         // Send acknowledgment
//         json response = {
//             "type": "waypoint_approaching_ack",
//             "driver_id": driverId,
//             "status": "received",
//             "timestamp": time:utcNow()
//         };
        
//         check caller->writeMessage(response);
//     } else {
//         log:printError("Invalid waypoint approaching message format", parseResult);
//         check sendErrorResponse(caller, "Invalid waypoint approaching message format");
//     }
// }

// // Handle pickup arrival
// function handlePickupArrival(websocket:Caller caller, json message) returns websocket:Error? {
//     common:PickupArrivalMessage|error parseResult = message.cloneWithType();
    
//     if parseResult is common:PickupArrivalMessage {
//         string driverId = parseResult.driver_id;
//         string rideId = parseResult.ride_id;
//         string passengerName = parseResult.passenger_name;
        
//         // Console log
//         io:println("=== PICKUP ARRIVAL ===");
//         io:println("Driver ID: " + driverId);
//         io:println("Ride ID: " + rideId);
//         io:println("Passenger Name: " + passengerName);
//         io:println("Timestamp: " + parseResult.timestamp);
//         io:println("======================");
        
//         // Send acknowledgment
//         json response = {
//             "type": "pickup_arrival_ack",
//             "driver_id": driverId,
//             "status": "received",
//             "timestamp": time:utcNow()
//         };
        
//         check caller->writeMessage(response);
//     } else {
//         log:printError("Invalid pickup arrival message format", parseResult);
//         check sendErrorResponse(caller, "Invalid pickup arrival message format");
//     }
// }

// // Handle passenger picked up
// function handlePassengerPickedUp(websocket:Caller caller, json message) returns websocket:Error? {
//     common:PassengerPickedUpMessage|error parseResult = message.cloneWithType();
    
//     if parseResult is common:PassengerPickedUpMessage {
//         string driverId = parseResult.driver_id;
//         string rideId = parseResult.ride_id;
//         string passengerName = parseResult.passenger_name;
        
//         // Console log
//         io:println("=== PASSENGER PICKED UP ===");
//         io:println("Driver ID: " + driverId);
//         io:println("Ride ID: " + rideId);
//         io:println("Passenger Name: " + passengerName);
//         io:println("Timestamp: " + parseResult.timestamp);
//         io:println("===========================");
        
//         // Send acknowledgment
//         json response = {
//             "type": "passenger_picked_up_ack",
//             "driver_id": driverId,
//             "status": "received",
//             "timestamp": time:utcNow()
//         };
        
//         check caller->writeMessage(response);
//     } else {
//         log:printError("Invalid passenger picked up message format", parseResult);
//         check sendErrorResponse(caller, "Invalid passenger picked up message format");
//     }
// }

// // Handle driver disconnection
// function handleDriverDisconnected(websocket:Caller caller, json message) returns websocket:Error? {
//     common:DriverDisconnectedMessage|error parseResult = message.cloneWithType();
    
//     if parseResult is common:DriverDisconnectedMessage {
//         string driverId = parseResult.driver_id;
//         string rideId = parseResult.ride_id;
        
//         // Console log
//         io:println("=== DRIVER DISCONNECTED ===");
//         io:println("Driver ID: " + driverId);
//         io:println("Ride ID: " + rideId);
//         io:println("Timestamp: " + parseResult.timestamp);
//         io:println("===========================");
        
//         // Remove from connected drivers
//         lock {
//             _ = connectedDrivers.remove(driverId);
//             _ = driverInfoMap.remove(driverId);
//         }
        
//         io:println("Remaining Connected Drivers: " + connectedDrivers.length().toString());
//     } else {
//         log:printError("Invalid driver disconnected message format", parseResult);
//     }
// }

// // Send error response to client
// function sendErrorResponse(websocket:Caller caller, string errorMessage) returns websocket:Error? {
//     json errorResponse = {
//         "type": "error",
//         "message": errorMessage,
//         "timestamp": time:utcNow()
//     };
    
//     check caller->writeMessage(errorResponse);
// }

// // Utility function to get current driver status
// function getCurrentDriverStatus() {
//     io:println("=== CURRENT DRIVER STATUS ===");
//     lock {
//         if connectedDrivers.length() == 0 {
//             io:println("No drivers currently connected");
//         } else {
//             io:println("Connected Drivers: " + connectedDrivers.length().toString());
            
//             foreach var [driverId, driverInfo] in driverInfoMap.entries() {
//                 io:println("Driver ID: " + driverId);
//                 io:println("Ride ID: " + driverInfo.rideId);
//                 io:println("Connection Time: " + driverInfo.connectionTime);
                
//                 if driverInfo.lastLatitude is decimal && driverInfo.lastLongitude is decimal {
//                     io:println("Last Location: " + driverInfo.lastLatitude.toString() + ", " + driverInfo.lastLongitude.toString());
//                 }
                
//                 if driverInfo.lastLocationUpdate is string {
//                     io:println( driverInfo.lastLocationUpdate);
//                 }
                
//                 io:println("---");
//             }
//         }
//     }
//     io:println("=============================");
// }

// // Function to broadcast message to all connected drivers (utility function)
// function broadcastToAllDrivers(json message) returns websocket:Error? {
//     lock {
//         foreach var [driverId, caller] in connectedDrivers.entries() {
//             websocket:Error? result = caller->writeMessage(message);
//             if result is websocket:Error {
//                 log:printError("Error broadcasting message to driver: " + driverId, result);
//             }
//         }
//     }
// }

// // Main function to start the service
// public function main() returns error? {
//     io:println("=== LOCATION TRACKING WEBSOCKET SERVICE ===");
//     io:println("Starting WebSocket service on " + host + ":" + port.toString());
//     io:println("WebSocket endpoint: ws://" + host + ":" + port.toString() + "/ws");
//     io:println("==========================================");
    
//     // The service will automatically start when the application runs
//     // You can add any additional initialization logic here
    
//     // Optional: Print status every 60 seconds
//     // Note: Removed periodic status check as runtime:sleep is deprecated
//     // You can implement this using scheduled tasks if needed
    
//     getCurrentDriverStatus();
// }