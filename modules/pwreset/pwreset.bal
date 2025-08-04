import ballerina/http;
import ballerina/random;
import 'service.utility;
import 'service.firebase;
import ballerina/email;
import ballerina/io;
import ballerina/time;
import 'service.auth;


email:SmtpClient smtpClient = check new (
    host = "smtp.gmail.com",
    port = 465,
    username = "nalakadineshx@gmail.com",
    password = "ihuv sgsh ddng ljfu",
    security = email:SSL
);


public function forgotPassword(http:Request req) returns http:Response|error{
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    string email = check payload.email;
    map<json> queryFilter = {"email": email};
     
    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }
    // First, get the specific ride document
    map<json>[]|error rideDoc = firebase:queryFirestoreDocuments(
            "carpooling-c6aa5",
            accessToken,
            "users",
            queryFilter
    );

    if rideDoc is error {
        return utility:createErrorResponse(500, "Failed to fetch user document");
    }

    if rideDoc.length() == 0 {
        return utility:createErrorResponse(404, "User not found");
    }
    string|error otp = generateOTP();
    if(otp is error){
        return utility:createErrorResponse(500,"Error sending otp");
    }
    email:Message emailMessage = {
    to: [email],
    subject: "Password Reset Request",
    body: string `
        <html>
        <body>
            <h2>Password Reset Request</h2>
            <p>You have requested to reset your password. Use the otp below to reset your password:</p>
            <p>${otp}</p>
            <p>This otp will expire in 1 minute.</p>
            <p>If you did not request this password reset, please ignore this email.</p>
            <br>
            <p>Best regards,<br>Carpool Team</p>
        </body>
        </html>
    `
    };
    
    email:Error? emailResult = smtpClient->sendMessage(emailMessage);
    if emailResult is email:Error {
        io:println("Email sending failed: " + emailResult.message());
        return utility:createErrorResponse(500, "Failed to send email: " + emailResult.message());
    }
    
    // Store current time as Unix timestamp for easier parsing
    time:Utc currentTimeUtc = time:utcNow();
    int currentTimestamp = currentTimeUtc[0]; // Get seconds from Utc tuple
    
    map<json> passwordReset = {
        "email": email,
        "otp": otp,
        "createdAtTimestamp": currentTimestamp, // Use specific field name for timestamp
        "createdAt": time:utcToString(currentTimeUtc) // Keep formatted version for readability
    };
    json|error createResult = firebase:createFirestoreDocument(
            "carpooling-c6aa5",
            accessToken,
            "passwordreset",
            passwordReset
    );
    
    if(createResult is error){
         return utility:createErrorResponse(500, "Failed to send email");
    }

    io:println("Email sent successfully to: " + email);
    return utility:createSuccessResponse(200, "OTP sent to email");
}

function generateOTP() returns string|error {
    int otp = check random:createIntInRange(1000, 9999);
    return otp.toString();
}

public function resetPassword(http:Request req) returns http:Response|error {
    json|error payload = req.getJsonPayload();
    if payload is error {
        return utility:createErrorResponse(400, "Invalid JSON payload");
    }

    string email = check payload.email;
    string otp = check payload.otp;
    string newPassword = check payload.newPassword;

    string|error accessToken = firebase:generateAccessToken();
    if accessToken is error {
        return utility:createErrorResponse(500, "Authentication failed");
    }

    // Query for OTP record by email
    map<json> otpQueryFilter = {"email": email};
    map<json>[]|error otpRecords = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        accessToken,
        "passwordreset",
        otpQueryFilter
    );

    if otpRecords is error {
        return utility:createErrorResponse(500, "Failed to verify OTP");
    }

    if otpRecords.length() == 0 {
        return utility:createErrorResponse(400, "No OTP found for this email");
    }

    // Get the most recent OTP record
    map<json> latestOtpRecord = otpRecords[otpRecords.length() - 1];
    string storedOtp = check latestOtpRecord.otp;
    
    if storedOtp != otp {
        return utility:createErrorResponse(400, "Invalid OTP");
    }

    map<json> userQueryFilter = {"email": email};
    map<json>[]|error userRecords = firebase:queryFirestoreDocuments(
        "carpooling-c6aa5",
        accessToken,
        "users",
        userQueryFilter
    );

    if userRecords is error {
        return utility:createErrorResponse(500, "Failed to find user");
    }

    if userRecords.length() == 0 {
        return utility:createErrorResponse(404, "User not found");
    }

    // Get user document ID
    map<json> userRecord = userRecords[0];
    string userId = check userRecord.id;

    string hashPassword = auth:hashPassword(newPassword);
    // Update password
    map<json> updateData = {
        "passwordHash": hashPassword
    };
    
    json|error updateResult = firebase:mergeFirestoreDocument(
        "carpooling-c6aa5",
        accessToken,
        "users",
        userId,
        updateData
    );

    if updateResult is error {
        return utility:createErrorResponse(500, "Failed to update password");
    }

    // Note: OTP record cleanup can be handled by a scheduled job or TTL in Firebase
    io:println("Password reset successfully for user: " + email);

    return utility:createSuccessResponse(200, "Password reset successfully");
}