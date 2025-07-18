public type GoogleCredentials record {|
    string serviceAccountJsonPath;
    string privateKeyFilePath;
    string tokenScope;
|};

public type user record {|
    string userId;
    string firstname;
    string lastname;
    string email;
    string phone;
    string password;
    string role;
    boolean status;
|};

public type vehicle record{|
    string userId;
    string vehicleType;
    string vehicleModel;
    string vehicleRegNumber;
    int noOfSeat;
|};


public type rideDetails record {|
    string rideId;
    
|};


public type RideData record {
    string pickupLocation;
    string dropoffLocation;
    string date;
    string startTime;
    string returnTime;
    string vehicleRegNo;
    RouteInfo route;
    string createdAt?;
    string rideId?;
};

public type RouteInfo record {
    int index;
    string duration;
    string distance;
    LatLng[] polyline;
};

public type LatLng record {
    decimal latitude;
    decimal longitude;
};

//websocket


public type CallRequest record {
    string callerPhone;
    string calleePhone;
};

public type CallResponse record {
    boolean success;
    string message;
    string? callSid;
};

public type ErrorResponse record {
    boolean success = false;
    string message;
    string? errorCode;
};