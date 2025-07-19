import 'service.firebase;
import 'service.notification;
import 'service.utility;

import ballerina/http;
import ballerina/uuid;

public function call(http:Request req) returns http:Response|error {
    json payload = check req.getJsonPayload();
    string callerId = check payload.callerId.ensureType();
    string receiverId = check payload.receiverId.ensureType();
    string channelName = uuid:createType1AsString();
    string callId = uuid:createType1AsString();

    // Generate Agora token (placeholder; use Agora SDK or REST API in production)

    // Store call details in Firestore
    map<json> callData = {
            "callerId": callerId,
            "receiverId": receiverId,
            "channelName": channelName,
            "status": "initiated"
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
        "channelName": channelName
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
            "channelName": channelName
        };
    return utility:createSuccessResponse(200, response);
}
