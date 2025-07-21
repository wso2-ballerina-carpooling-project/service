import ballerina/crypto;
import ballerina/time;

const int EXPIRATION_TIME_IN_SECONDS = 3600;
const int VERSION = 1;


public function generateAgoraToken(string channelName, string uid, string appId, string appCertificate) returns string|error {
        time:Utc currentTime = time:utcNow();
        int currentTimestamp = currentTime[0];
        int privilegeExpiredTs = currentTimestamp + EXPIRATION_TIME_IN_SECONDS;

        // Construct message for signing
        string message = string `${appId}${channelName}${uid}${privilegeExpiredTs}`;
        
        byte[] key = appCertificate.toBytes();
        byte[] data = message.toBytes();
        
        // Generate signature using HMAC-SHA256
        byte[] hmac = check crypto:hmacSha256(data, key);
        string signature = hmac.toBase64();

        // Construct token
        string token = string `${VERSION}:${appId}:${channelName}:${uid}:${privilegeExpiredTs}:${signature}`;
        
        return token;
}

