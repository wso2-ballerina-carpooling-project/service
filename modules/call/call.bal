import ballerina/http;
import ballerina/mime;

const string TWILIO_ACCOUNT_SID = "AC828160a52c3ccdb696fd99a524662d82";
const string TWILIO_AUTH_TOKEN = "836d2499fff74750ab2cfd19eeed1829";
const string FLOW_ID = "FWe8478ba2c5c783e39e1cf3b37ac736b3";
const string BASE_URL = "https://studio.twilio.com/v2";

// HTTP client with basic auth
http:Client twilioClient = check new (BASE_URL, {
    auth: {
        username: TWILIO_ACCOUNT_SID,
        password: TWILIO_AUTH_TOKEN
    }
});

public function executeFlow(string toNumber, string fromNumber) returns json|error {
    // Prepare form data
    string formData = string `To=${toNumber}&From=${fromNumber}`;
    
    // Set headers
    map<string> headers = {
        "Content-Type": mime:APPLICATION_FORM_URLENCODED
    };
    
    // Make the POST request
    http:Response response = check twilioClient->post(
        string `/Flows/${FLOW_ID}/Executions`,
        formData,
        headers
    );
    
    // Return the JSON response
    return response.getJsonPayload();
}

// Alternative function with error handling and return type
public function executeTwilioFlow(string toNumber, string fromNumber) returns ExecutionResult|error {
    json response = check executeFlow(toNumber, fromNumber);
    
    return {
        success: true,
        data: response,
        message: "Flow executed successfully"
    };
}

// Response type definition
public type ExecutionResult record {
    boolean success;
    json data?;
    string message;
};

public function formatSriLankanPhoneNumber(string phone) returns string {
    // Remove any whitespace
    string cleanPhone = phone.trim();
    
    // If phone starts with "0", remove it and add "+94"
    if cleanPhone.startsWith("0") {
        return "+94" + cleanPhone.substring(1);
    }
    
    // If phone starts with "94", add "+"
    if cleanPhone.startsWith("94") {
        return "+" + cleanPhone;
    }
    
    // If phone already starts with "+94", return as is
    if cleanPhone.startsWith("+94") {
        return cleanPhone;
    }
    
    // For any other case, assume it's a local number without leading 0
    return "+94" + cleanPhone;
}