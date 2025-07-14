import ballerina/http;
import ballerina/log;
import 'service.firebase_auth;


configurable string ACCOUNT_SID = ?;
configurable string AUTH_TOKEN = ?;
configurable string MESSAGING_SERVICE_SID = ?;
configurable firebase_auth:ServiceAccount serviceAccount = ?;
configurable string keyPath = ?;

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

public function sendFCMNotification(string deviceToken, string title, string body, string projectId) returns string|error {
    string accessToken = check generateAccessTokenFCM();
    
    // Prepare FCM payload
    FCMPayload payload = {
        message: {
            token: deviceToken,
            notification: {
                title: title,
                body: body
            }
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




public function sendSms(string to, string messageBody) returns error? {
    string url = string `https://api.twilio.com/2010-04-01/Accounts/${ACCOUNT_SID}/Messages.json`;

    http:Client twilioClient = check new (url, {
        auth: {
            username: ACCOUNT_SID,
            password: AUTH_TOKEN
        }
    });

    map<string> formData = {
        "To": to,
        "MessagingServiceSid": MESSAGING_SERVICE_SID,
        "Body": messageBody
    };

    http:Response response = check twilioClient->post("", formData, {
        "Content-Type": "application/x-www-form-urlencoded"
    });
    json result = check response.getJsonPayload();
    log:printInfo("📲 SMS Sent. Twilio SID: " + result.toJsonString());
}