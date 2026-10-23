public without sharing class OpportunityOnboardingHandler {
    public static void afterSave(
        List<Opportunity> records,
        Map<Id, Opportunity> oldMap
    ) {
        Map<Id, Opportunity> newlyWon = new Map<Id, Opportunity>();

        for (Opportunity deal : records) {
            Boolean wasWon =
                oldMap != null &&
                oldMap.get(deal.Id).IsWon;

            if (deal.IsWon && !wasWon) {
                newlyWon.put(deal.Id, deal);
            }
        }

        if (newlyWon.isEmpty()) {
            return;
        }

        Set<Id> existingOpportunityIds = new Set<Id>();

        for (Onboarding__c onboarding : [
            SELECT Opportunity__c
            FROM Onboarding__c
            WHERE Opportunity__c IN :newlyWon.keySet()
        ]) {
            existingOpportunityIds.add(onboarding.Opportunity__c);
        }

        List<Onboarding__c> toCreate = new List<Onboarding__c>();

        for (Opportunity deal : records) {
            if (
                !newlyWon.containsKey(deal.Id) ||
                existingOpportunityIds.contains(deal.Id)
            ) {
                continue;
            }

            Date launchDate = deal.Expected_Launch_Date__c;

            if (launchDate == null) {
                launchDate = deal.CloseDate.addDays(30);
            }

            toCreate.add(new Onboarding__c(
                Opportunity__c = deal.Id,
                Expected_Launch_Date__c = launchDate,
                Stage__c = 'Kickoff Scheduled'
            ));
        }

        if (!toCreate.isEmpty()) {
            insert toCreate;
        }
    }
}