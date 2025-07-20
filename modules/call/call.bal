import 'service.firebase;
import 'service.notification;
import 'service.utility;
import ballerina/crypto;
import ballerina/time;
import ballerina/http;
import ballerina/uuid;

configurable string agoraAppId = ?;
configurable string agoraAppCertificate = ?;

// Agora token constants
const int SERVICE_TYPE_RTC = 1;
const int PRIVILEGE_JOIN_CHANNEL = 1;
const int PRIVILEGE_PUBLISH_AUDIO_STREAM = 2;
const int PRIVILEGE_PUBLISH_VIDEO_STREAM = 3;
const int PRIVILEGE_PUBLISH_DATA_STREAM = 4;

public function call(http:Request req) returns http:Response|error {
    json payload = check req.getJsonPayload();
    string callerId = check payload.callerId.ensureType();
    string receiverId = check payload.receiverId.ensureType();
    string channelName = uuid:createType1AsString();
    string callId = uuid:createType1AsString();

    // Generate Agora token (placeholder; use Agora SDK or REST API in production)
    int uid = 0; // Use 0 for dynamic UID assignment
    int expirationTimeInSeconds = 3600; // 1 hour
    string|error token = generateAgoraToken(channelName, uid, expirationTimeInSeconds);
    if(token is error){
        return utility:createErrorResponse(404,"Not work");
    }

    // Store call details in Firestore
    map<json> callData = {
            "callId": callId,
            "callerId": callerId,
            "receiverId": receiverId,
            "channelName": channelName,
            "token": token,
            "status": "initiated",
            "timestamp": time:utcToString(time:utcNow())
        };
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }

    json|error createResult = firebase:createFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "call",
            callData
        );

    json|error queryResult = firebase:getFirestoreDocumentById(
            "carpooling-c6aa5",
            accessToken,
            "users",
            receiverId
        );

    if (queryResult is error) {
        return utility:createErrorResponse(400, "Server error");
    }

    map<string> data = {
        "callId": callId,
        "callerId": callerId,
        "channelName": channelName,
        "token":token
    };
    // Get receiver's FCM token
    if (queryResult is json) {
        if (queryResult is map<json>) {
            string fcm = queryResult["fcm"].toString();
            string|error notifi = notification:sendFCMNotification(fcm, "Calling", "Carpool Driver Calling", "carpooling-c6aa5", data);
        }
    }

    // Send FCM notification
    // fcm:Message message = {
    //     token: receiverFcmToken,
    //     notification: {
    //         title: "Incoming Call",
    //         body: "Call from user"
    //     },
    //     data: {
    //         "callId": callId,
    //         "callerId": callerId,
    //         "channelName": channelName,
    //         "agoraToken": agoraToken
    //     }
    // };
    // check fcmClient->send(message);

    // Respond to caller
    json response = {
            "callId": callId,
            "channelName": channelName,
            "callerName" :"Nalaka",
            "token":token,
            "status": "initiated"
        };
    return utility:createSuccessResponse(200, response);
}

public function generateAgoraToken(string channelName, int uid, int expirationTimeInSeconds) returns string|error {
    return buildRtcToken(agoraAppId, agoraAppCertificate, channelName, uid, "publisher", expirationTimeInSeconds);
}

function buildRtcToken(string appId, string appCertificate, string channelName, 
                      int uid, string role, int expirationTimeInSeconds) returns string|error {
    
    // Current timestamp
    int currentTimestamp = time:utcNow()[0];
    int privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;
    
    // Convert uid to string for token generation
    string uidStr = uid.toString();
    
    // Build privileges based on role
    map<int> privileges = {};
    if (role == "publisher" || role == "host") {
        privileges[PRIVILEGE_JOIN_CHANNEL.toString()] = privilegeExpiredTs;
        privileges[PRIVILEGE_PUBLISH_AUDIO_STREAM.toString()] = privilegeExpiredTs;
        privileges[PRIVILEGE_PUBLISH_VIDEO_STREAM.toString()] = privilegeExpiredTs;
        privileges[PRIVILEGE_PUBLISH_DATA_STREAM.toString()] = privilegeExpiredTs;
    } else {
        // Subscriber role - only join channel privilege
        privileges[PRIVILEGE_JOIN_CHANNEL.toString()] = privilegeExpiredTs;
    }
    
    // Create the message to be signed
    string message = check buildTokenMessage(appId, channelName, uidStr, currentTimestamp, privilegeExpiredTs, privileges);
    
    // Generate HMAC SHA256 signature
    byte[] messageBytes = message.toBytes();
    byte[] keyBytes = appCertificate.toBytes();
    byte[] signature = check crypto:hmacSha256(messageBytes, keyBytes);
    
    // Encode signature to base64
    string signatureBase64 = signature.toBase64();
    
    // Build final token: version + appId + signature + message
    string version = "007";
    string token = version + appId + signatureBase64 + message;
    
    return token;
}

function buildTokenMessage(string appId, string channelName, string uid, 
                          int timestamp, int expireTs, map<int> privileges) returns string|error {
    
    // Create message components
    string[] components = [];
    
    // Service type (RTC = 1)
    components.push(packUint32(SERVICE_TYPE_RTC));
    
    // App ID
    components.push(packString(appId));
    
    // Channel name
    components.push(packString(channelName));
    
    // UID
    components.push(packString(uid));
    
    // Issue timestamp
    components.push(packUint32(timestamp));
    
    // Expire timestamp  
    components.push(packUint32(expireTs));
    
    // Salt (random number, using timestamp for simplicity)
    components.push(packUint32(timestamp % 1000000));
    
    // Privileges
    components.push(packPrivileges(privileges));
    
    // Join all components
    string message = "";
    foreach string component in components {
        message += component;
    }
    
    return message;
}

function packString(string str) returns string {
    byte[] strBytes = str.toBytes();
    return packUint16(strBytes.length()) + strBytes.toBase64();
}

function packUint16(int value) returns string {
    // Pack as little-endian 16-bit unsigned integer
    int byte0 = value & 0xFF;
    int byte1 = (value >> 8) & 0xFF;
    byte[] bytes = [<byte>byte0, <byte>byte1];
    return bytes.toBase64();
}

function packUint32(int value) returns string {
    // Pack as little-endian 32-bit unsigned integer
    int byte0 = value & 0xFF;
    int byte1 = (value >> 8) & 0xFF;
    int byte2 = (value >> 16) & 0xFF;
    int byte3 = (value >> 24) & 0xFF;
    byte[] bytes = [<byte>byte0, <byte>byte1, <byte>byte2, <byte>byte3];
    return bytes.toBase64();
}

function packPrivileges(map<int> privileges) returns string {
    string result = packUint16(privileges.length());
    
    foreach var [key, expireTime] in privileges.entries() {
        int privilegeId = checkpanic int:fromString(key);
        result += packUint16(privilegeId);
        result += packUint32(expireTime);
    }
    
    return result;
}

// Alternative function that matches your original signature exactly
public function generateAgoraTokenSimple(string channelName, int uid, int expirationTimeInSeconds) returns string {
    string|error token = generateAgoraToken(channelName, uid, expirationTimeInSeconds);
    if token is error {
        // Return empty string or handle error as needed
        return "";
    }
    return token;
}

// Example usage with your data map
public function createCallData(string callId, string callerId, string channelName) returns map<string>|error {
    int uid = check int:fromString(callerId); // Convert callerId to int if needed
    string token = check generateAgoraToken(channelName, uid, 3600); // 1 hour expiry
    
    map<string> data = {
        "callId": callId,
        "callerId": callerId,
        "channelName": channelName,
        "token": token
    };
    
    return data;
}