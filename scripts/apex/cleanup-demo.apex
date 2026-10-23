String batchName = 'Revinfinity Bulk 1792738512208';

List<Onboarding__c> demoRecords = [
    SELECT Id
    FROM Onboarding__c
    WHERE Opportunity__r.Account.Name = :batchName
];

System.assert(
    demoRecords.size() <= 200,
    'More than 200 matching records found. Cleanup stopped.'
);

delete demoRecords;

System.debug(
    LoggingLevel.ERROR,
    'DEMO ONBOARDINGS DELETED: ' + demoRecords.size()
);