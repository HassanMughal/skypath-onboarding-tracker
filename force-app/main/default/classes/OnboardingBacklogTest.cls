@IsTest
private class OnboardingBacklogTest {
    @TestSetup
    static void prepareQueue() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
              AND DeveloperName = 'Onboarding_Backlog'
            LIMIT 1
        ];

        Group backlog;

        if (queues.isEmpty()) {
            backlog = new Group(
                Name = 'Onboarding Backlog',
                DeveloperName = 'Onboarding_Backlog',
                Type = 'Queue'
            );
            insert backlog;
        } else {
            backlog = queues[0];
        }

        List<QueueSobject> supportedObjects = [
            SELECT Id
            FROM QueueSobject
            WHERE QueueId = :backlog.Id
              AND SobjectType = 'Onboarding__c'
        ];

        if (supportedObjects.isEmpty()) {
            insert new QueueSobject(
                QueueId = backlog.Id,
                SobjectType = 'Onboarding__c'
            );
        }

        List<GroupMember> members = [
            SELECT Id
            FROM GroupMember
            WHERE GroupId = :backlog.Id
              AND UserOrGroupId = :UserInfo.getUserId()
        ];

        if (members.isEmpty()) {
            insert new GroupMember(
                GroupId = backlog.Id,
                UserOrGroupId = UserInfo.getUserId()
            );
        }
    }

    @IsTest
    static void respectsCapacityFor200Deals() {
        insert new CSM_Configuration__c(
            Name = 'Capacity Two CSM',
            CSM_User__c = UserInfo.getUserId(),
            Eligible__c = true,
            Maximum_Capacity__c = 2
        );

        Account customer = new Account(
            Name = 'Capacity Test Customer'
        );
        insert customer;

        List<Opportunity> deals = new List<Opportunity>();

        for (Integer i = 0; i < 200; i++) {
            deals.add(new Opportunity(
                Name = 'Capacity Test Deal ' + i,
                AccountId = customer.Id,
                CloseDate = Date.today(),
                StageName = 'Prospecting'
            ));
        }

        insert deals;

        for (Opportunity deal : deals) {
            deal.StageName = 'Closed Won';
        }

        Test.startTest();

        update deals;

        Test.stopTest();

        Group backlog = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
              AND DeveloperName = 'Onboarding_Backlog'
            LIMIT 1
        ];

        Set<Id> dealIds = new Map<Id, Opportunity>(deals).keySet();

        List<Onboarding__c> onboardings = [
            SELECT OwnerId, Opportunity__c, Stage__c
            FROM Onboarding__c
            WHERE Opportunity__c IN :dealIds
        ];

        System.assertEquals(
            200, onboardings.size(),
            'All 200 won deals must receive onboardings.'
        );

        Integer assignedCount = 0;
        Integer backlogCount = 0;
        Set<Id> linkedDeals = new Set<Id>();

        for (Onboarding__c onboarding : onboardings) {
            linkedDeals.add(onboarding.Opportunity__c);

            System.assertEquals(
                'Kickoff Scheduled',
                onboarding.Stage__c,
                'All new records must start at Kickoff Scheduled.'
            );

            if (onboarding.OwnerId == UserInfo.getUserId()) {
                assignedCount++;
            } else if (onboarding.OwnerId == backlog.Id) {
                backlogCount++;
            } else {
                System.assert(
                    false,
                    'Unexpected onboarding owner: ' + onboarding.OwnerId
                );
            }
        }

        System.assertEquals(
            200, linkedDeals.size(),
            'Every deal must have its own onboarding.'
        );
        System.assertEquals(
            2, assignedCount,
            'The CSM must receive exactly two active onboardings.'
        );
        System.assertEquals(
            198, backlogCount,
            'The remaining 198 must go to the shared backlog.'
        );
    }
}