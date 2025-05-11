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
