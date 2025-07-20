import ballerina/http;
import ballerina/log;
import 'service.firebase_auth;
import ballerinax/twilio;
import ballerina/io;


configurable firebase_auth:ServiceAccount serviceAccount = ?;
configurable string keyPath = ?;
configurable string apiKey = ?;
configurable string apiSecret = ?;
configurable string accountSid = ?;

twilio:ConnectionConfig twilioConfig = {
    auth: {
        apiKey,
        apiSecret,
        accountSid
    }
};

twilio:Client twilio = check new (twilioConfig);

function generateAccessTokenFCM() returns string|error {
    firebase_auth:AuthConfig authConfig = {
        privateKeyPath: keyPath,
        jwtConfig: {
            expTime: 3600,
            scope: "https://www.googleapis.com/auth/firebase.messaging"
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

type FCMMessage record {|
    string token;
    record {|
        string title;
        string body;
        string? image?;
    |} notification;
    record {|
        string? click_action?;
        string? sound?;
    |}? android?;
    record {|
        string? sound?;
        int? badge?;
    |}? apns?;
    map<string>? data?;
|};

type FCMPayload record {|
    FCMMessage message;
|};
final string FCM_BASE_URL = "https://fcm.googleapis.com/v1/projects/";

public function sendFCMNotification(string deviceToken, string title, string body, string projectId,map<string> data={}) returns string|error {
    string accessToken = check generateAccessTokenFCM();
    
    // Prepare FCM payload
    FCMPayload payload = {
        message: {
            token: deviceToken,
            notification: {
                title: title,
                body: body
            },
            data: data
        }
    };
    
    // Send to FCM
    string fcmEndpoint = FCM_BASE_URL + projectId + "/messages:send";
    http:Client fcmClient = check new (fcmEndpoint, {
        timeout: 30
    });
    
    http:Response res = check fcmClient->post("", payload, {
        "Authorization": "Bearer " + accessToken,
        "Content-Type": "application/json"
    });
    
    if res.statusCode == 200 {
        json responseBody = check res.getJsonPayload();
        log:printInfo("✅ Push sent successfully. Status: " + res.statusCode.toString());
        return responseBody.toJsonString();
    } else {
        string errorMsg = check res.getTextPayload();
        log:printError("❌ Push failed. Status: " + res.statusCode.toString() + " Error: " + errorMsg);
        return error("FCM request failed: " + errorMsg);
    }
}

public function sendsms(string number,string massage) returns error? {
    twilio:CreateMessageRequest messageRequest = {
        To: number, 
        From: "+13185953040", 
        Body: massage
    };

    twilio:Message response = check twilio->createMessage(messageRequest);
    io:print(response);
}



