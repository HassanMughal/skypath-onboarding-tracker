String batchName =
    'Revinfinity Bulk ' + String.valueOf(System.now().getTime());

Account customer = new Account(Name = batchName);
insert customer;

List<Opportunity> deals = new List<Opportunity>();

for (Integer i = 0; i < 200; i++) {
    deals.add(new Opportunity(
        Name = batchName + ' Deal ' + i,
        AccountId = customer.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today(),
        Expected_Launch_Date__c = Date.today().addDays(30)
    ));
}

insert deals;

for (Opportunity deal : deals) {
    deal.StageName = 'Closed Won';
}

// Close all 200 Opportunities in one update.
update deals;

Set<Id> dealIds = new Map<Id, Opportunity>(deals).keySet();

Integer onboardingCount = [
    SELECT COUNT()
    FROM Onboarding__c
    WHERE Opportunity__c IN :dealIds
];

System.assertEquals(
    200,
    onboardingCount,
    'Every Opportunity must receive one onboarding.'
);

System.debug(LoggingLevel.ERROR, 'DEMO ACCOUNT: ' + batchName);
System.debug(
    LoggingLevel.ERROR,
    'ONBOARDINGS CREATED: ' + onboardingCount
);

for (AggregateResult allocation : [
    SELECT OwnerId owner, COUNT(Id) quantity
    FROM Onboarding__c
    WHERE Opportunity__c IN :dealIds
    GROUP BY OwnerId
]) {
    System.debug(
        LoggingLevel.ERROR,
        'OWNER ' + allocation.get('owner') +
        ' | ASSIGNED ' + allocation.get('quantity')
    );
}