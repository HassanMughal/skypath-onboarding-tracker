@IsTest
private class OnboardingAssessmentTest {
    @TestSetup
    static void createUsers() {
        String uniqueSuffix =
            UserInfo.getOrganizationId() + '.' +
            String.valueOf(Datetime.now().getTime());

        List<User> users = new List<User>();

        for (Integer i = 0; i < 2; i++) {
            users.add(new User(
                FirstName = 'Assessment',
                LastName = 'CSM ' + i,
                Alias = 'ascsm' + i,
                Email = 'assessment.csm' + i + '@example.com',
                Username =
                    'assessment.csm' + i + '.' +
                    uniqueSuffix + '@example.com',
                CommunityNickname =
                    'ascsm' + i + Datetime.now().getTime(),
                ProfileId = UserInfo.getProfileId(),
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            ));
        }

        insert users;
    }

    @IsTest
    static void assigns200WonDealsFairly() {
        List<User> csms = [
            SELECT Id
            FROM User
            WHERE Alias IN ('ascsm0', 'ascsm1')
            ORDER BY Alias
        ];

        System.assertEquals(
            2, csms.size(),
            'The test needs two temporary CSM users.'
        );

        List<CSM_Configuration__c> configs =
            new List<CSM_Configuration__c>();

        for (User csm : csms) {
            configs.add(new CSM_Configuration__c(
                Name = 'Test CSM ' + csm.Id,
                CSM_User__c = csm.Id,
                Eligible__c = true,
                Maximum_Capacity__c = 100
            ));
        }

        insert configs;

        Account customer = new Account(Name = 'Bulk Test Customer');
        insert customer;

        Date launchDate = Date.today().addDays(30);
        List<Opportunity> deals = new List<Opportunity>();

        for (Integer i = 0; i < 200; i++) {
            deals.add(new Opportunity(
                Name = 'Bulk Test Deal ' + i,
                AccountId = customer.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today(),
                Expected_Launch_Date__c = launchDate
            ));
        }

        insert deals;

        for (Opportunity deal : deals) {
            deal.StageName = 'Closed Won';
        }

        Test.startTest();

        // Close all 200 deals in one update statement.
        update deals;

        Test.stopTest();

        Set<Id> dealIds = new Map<Id, Opportunity>(deals).keySet();

        List<Onboarding__c> onboardings = [
            SELECT Opportunity__c, OwnerId, Stage__c,
                   Expected_Launch_Date__c, Kickoff_First_Reached__c,
                   Opportunity_Key__c, Name
            FROM Onboarding__c
            WHERE Opportunity__c IN :dealIds
        ];

        System.assertEquals(
            200, onboardings.size(),
            'Every won deal must receive an onboarding.'
        );

        Map<Id, Integer> workloads = new Map<Id, Integer>{
            csms[0].Id => 0,
            csms[1].Id => 0
        };

        Set<Id> linkedDeals = new Set<Id>();

        for (Onboarding__c onboarding : onboardings) {
            System.assert(
                workloads.containsKey(onboarding.OwnerId),
                'Every onboarding must belong to an eligible CSM.'
            );

            workloads.put(
                onboarding.OwnerId,
                workloads.get(onboarding.OwnerId) + 1
            );

            linkedDeals.add(onboarding.Opportunity__c);

            System.assertEquals(
                'Kickoff Scheduled', onboarding.Stage__c,
                'New onboardings must start at Kickoff Scheduled.'
            );
            System.assertEquals(
                launchDate, onboarding.Expected_Launch_Date__c,
                'The planned launch date must be copied.'
            );
            System.assertNotEquals(
                null, onboarding.Kickoff_First_Reached__c,
                'The first stage timestamp must be populated.'
            );
            System.assertEquals(
                String.valueOf(onboarding.Opportunity__c),
                onboarding.Opportunity_Key__c,
                'The unique key must match the linked Opportunity.'
            );
            System.assertEquals(
                'Bulk Test Customer | Launch ' +
                String.valueOf(launchDate),
                onboarding.Name,
                'The name must identify the customer and launch date.'
            );
        }

        System.assertEquals(
            200, linkedDeals.size(),
            'Each onboarding must reference a different deal.'
        );
        System.assertEquals(
            100, workloads.get(csms[0].Id),
            'The first CSM must receive exactly 100 onboardings.'
        );
        System.assertEquals(
            100, workloads.get(csms[1].Id),
            'The second CSM must receive exactly 100 onboardings.'
        );
    }

    private static Opportunity createWonDeal() {
        User csm = [
            SELECT Id
            FROM User
            WHERE Alias = 'ascsm0'
            LIMIT 1
        ];

        insert new CSM_Configuration__c(
            Name = 'Test CSM',
            CSM_User__c = csm.Id,
            Eligible__c = true,
            Maximum_Capacity__c = 10
        );

        Account customer = new Account(Name = 'Scenario Customer');
        insert customer;

        Opportunity deal = new Opportunity(
            Name = 'Scenario Deal',
            AccountId = customer.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today()
        );

        insert deal;
        return deal;
    }

    @IsTest
    static void reopeningDoesNotDuplicateOnboarding() {
        Opportunity deal = createWonDeal();

        Onboarding__c original = [
            SELECT Id, Expected_Launch_Date__c
            FROM Onboarding__c
            WHERE Opportunity__c = :deal.Id
        ];

        System.assertEquals(
            deal.CloseDate.addDays(30),
            original.Expected_Launch_Date__c,
            'Missing launch date must use Close Date plus 30 days.'
        );

        Test.startTest();

        deal.StageName = 'Prospecting';
        update deal;

        deal.StageName = 'Closed Won';
        update deal;

        Test.stopTest();

        List<Onboarding__c> results = [
            SELECT Id
            FROM Onboarding__c
            WHERE Opportunity__c = :deal.Id
        ];

        System.assertEquals(
            1, results.size(),
            'Reopening and winning must not create another onboarding.'
        );
        System.assertEquals(
            original.Id, results[0].Id,
            'The original onboarding must be preserved.'
        );
    }

    private static void assertBlocked(
        Onboarding__c change,
        String expectedMessage
    ) {
        Database.SaveResult result = Database.update(change, false);

        System.assertEquals(
            false, result.isSuccess(),
            'This invalid update must be rejected.'
        );
        System.assert(
            result.getErrors()[0].getMessage().contains(expectedMessage),
            'Unexpected error: ' + result.getErrors()[0].getMessage()
        );
    }

    @IsTest
    static void enforcesStagesAndPreservesHistory() {
        Opportunity deal = createWonDeal();

        Onboarding__c onboarding = [
            SELECT Id, Kickoff_First_Reached__c
            FROM Onboarding__c
            WHERE Opportunity__c = :deal.Id
        ];

        Datetime originalKickoff = onboarding.Kickoff_First_Reached__c;

        Test.startTest();

        // Skipping Gathering Info must fail.
        assertBlocked(
            new Onboarding__c(
                Id = onboarding.Id,
                Stage__c = 'Implementation'
            ),
            'Move forward one stage at a time'
        );

        update new Onboarding__c(
            Id = onboarding.Id,
            Stage__c = 'Gathering Info'
        );

        // Entering Implementation without gathering notes must fail.
        assertBlocked(
            new Onboarding__c(
                Id = onboarding.Id,
                Stage__c = 'Implementation'
            ),
            'Enter Gathering Notes'
        );

        update new Onboarding__c(
            Id = onboarding.Id,
            Stage__c = 'Implementation',
            Gathering_Notes__c = 'Requirements confirmed.'
        );

        // Entering QA without implementation notes must fail.
        assertBlocked(
            new Onboarding__c(
                Id = onboarding.Id,
                Stage__c = 'QA / Review'
            ),
            'Enter Implementation Notes'
        );

        update new Onboarding__c(
            Id = onboarding.Id,
            Stage__c = 'QA / Review',
            Implementation_Notes__c = 'Configuration completed.'
        );

        Onboarding__c firstVisit = [
            SELECT Implementation_First_Reached__c,
                   QA_First_Reached__c
            FROM Onboarding__c
            WHERE Id = :onboarding.Id
        ];

        System.assertNotEquals(
            null, firstVisit.Implementation_First_Reached__c,
            'Implementation must have a first-entry timestamp.'
        );
        System.assertNotEquals(
            null, firstVisit.QA_First_Reached__c,
            'QA must have a first-entry timestamp.'
        );

        // Failed QA can return work to Implementation.
        update new Onboarding__c(
            Id = onboarding.Id,
            Stage__c = 'Implementation'
        );

        update new Onboarding__c(
            Id = onboarding.Id,
            Stage__c = 'QA / Review'
        );

        // A manual edit must not replace a historical timestamp.
        update new Onboarding__c(
            Id = onboarding.Id,
            QA_First_Reached__c = System.now().addDays(-10)
        );

        update new Onboarding__c(
            Id = onboarding.Id,
            Stage__c = 'Go Live'
        );

        update new Onboarding__c(
            Id = onboarding.Id,
            Stage__c = 'Post-Launch Review'
        );

        Test.stopTest();

        Onboarding__c completed = [
            SELECT Stage__c, Kickoff_First_Reached__c,
                   Gathering_First_Reached__c,
                   Implementation_First_Reached__c,
                   QA_First_Reached__c,
                   Go_Live_First_Reached__c,
                   Post_Launch_First_Reached__c
            FROM Onboarding__c
            WHERE Id = :onboarding.Id
        ];

        System.assertEquals(
            'Post-Launch Review', completed.Stage__c,
            'The onboarding must reach the final stage.'
        );
        System.assertEquals(
            originalKickoff, completed.Kickoff_First_Reached__c,
            'The original Kickoff timestamp must be preserved.'
        );
        System.assertNotEquals(
            null, completed.Gathering_First_Reached__c,
            'Gathering Info must have a timestamp.'
        );
        System.assertEquals(
            firstVisit.Implementation_First_Reached__c,
            completed.Implementation_First_Reached__c,
            'Rework must preserve the first Implementation timestamp.'
        );
        System.assertEquals(
            firstVisit.QA_First_Reached__c,
            completed.QA_First_Reached__c,
            'QA revisits and manual edits must preserve the timestamp.'
        );
        System.assertNotEquals(
            null, completed.Go_Live_First_Reached__c,
            'Go Live must have a timestamp.'
        );
        System.assertNotEquals(
            null, completed.Post_Launch_First_Reached__c,
            'Post-Launch Review must have a timestamp.'
        );
    }
}