public without sharing class OnboardingTriggerHandler {
    public static void beforeSave(
        List<Onboarding__c> records,
        Map<Id, Onboarding__c> oldMap
    ) {
        Set<Id> opportunityIds = new Set<Id>();

        for (Onboarding__c record : records) {
            if (record.Opportunity__c != null) {
                opportunityIds.add(record.Opportunity__c);
            }

            if (oldMap != null) {
                Onboarding__c previous = oldMap.get(record.Id);

                if (record.Opportunity__c != previous.Opportunity__c) {
                    record.addError(
                        'The linked Opportunity cannot be changed.'
                    );
                }
            }
        }

        Map<Id, Opportunity> opportunities = new Map<Id, Opportunity>([
            SELECT Id, Name, Account.Name
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ]);

        for (Onboarding__c record : records) {
            Opportunity deal = opportunities.get(record.Opportunity__c);

            if (deal == null) {
                record.addError('Select a valid Opportunity.');
                continue;
            }

            // Always derive the unique key from the actual relationship.
            record.Opportunity_Key__c =
                String.valueOf(record.Opportunity__c);

            if (record.Expected_Launch_Date__c == null) {
                record.addError('Enter an Expected Launch Date.');
                continue;
            }

            String customerName = deal.Account == null
                ? deal.Name
                : deal.Account.Name;

            String suffix =
                ' | Launch ' +
                String.valueOf(record.Expected_Launch_Date__c);

            // Salesforce custom-object Name fields allow 80 characters.
            Integer availableLength = 80 - suffix.length();

            if (customerName.length() > availableLength) {
                customerName = customerName.substring(0, availableLength);
            }

            record.Name = customerName + suffix;
        }

        OnboardingStageService.applyRules(records, oldMap);

        if (oldMap == null) {
            OnboardingAssignmentService.assignNew(records);
        }
    }
}