import ballerina/http;
import ballerina/log;
import 'service.firebase as firebase;
import 'service.utility;

public function markPaymentAsPaid(json payload, http:Request req, string accessToken) returns http:Response|error {

    string|http:HeaderNotFoundError authHeader = req.getHeader("Authorization");
    if authHeader is http:HeaderNotFoundError {
        return utility:createErrorResponse(401, "Authorization header missing");
    }

    // Extract paymentId from payload
    string paymentId = check payload.paymentId;

    // Prepare the Firestore update body
    map<json> updateBody = {
        "isPaid": true
    };

    // Update the document in Firestore
    json|error updateResult = firebase:mergeFirestoreDocument(
        "carpooling-c6aa5",
        accessToken,
        "payments",
        paymentId,
        updateBody
    );

    if updateResult is error {
        log:printError("Error updating payment: " + updateResult.message());
        return utility:createErrorResponse(500, "Failed to mark payment as paid");
    }

    json successResponse = {
        "message": "Payment marked as paid"
    };

    http:Response response = new;
    response.statusCode = 200;
    response.setJsonPayload(successResponse);
    return response;
}