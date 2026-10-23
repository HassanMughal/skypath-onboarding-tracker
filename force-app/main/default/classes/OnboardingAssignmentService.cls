public without sharing class OnboardingAssignmentService {
    public static void assignNew(List<Onboarding__c> onboardings) {
        if (onboardings.isEmpty()) {
            return;
        }

        // Lock the roster before counting workload.
        // Other transactions using this service must acquire these locks.
        List<CSM_Configuration__c> roster = [
            SELECT Id, CSM_User__c, Maximum_Capacity__c,
                   Eligible__c, CSM_User__r.IsActive
            FROM CSM_Configuration__c
            FOR UPDATE
        ];

        Map<Id, Integer> capacities = new Map<Id, Integer>();
        Set<Id> configuredUsers = new Set<Id>();

        for (CSM_Configuration__c config : roster) {
            if (config.CSM_User__c == null) {
                continue;
            }

            // Fail clearly rather than silently accepting conflicting settings.
            if (configuredUsers.contains(config.CSM_User__c)) {
                for (Onboarding__c onboarding : onboardings) {
                    onboarding.addError(
                        'Duplicate CSM Configuration records exist for a user. ' +
                        'Ask your administrator to keep one per CSM.'
                    );
                }
                return;
            }

            configuredUsers.add(config.CSM_User__c);

            if (
                config.Eligible__c &&
                config.CSM_User__r.IsActive &&
                config.Maximum_Capacity__c != null &&
                config.Maximum_Capacity__c > 0
            ) {
                capacities.put(
                    config.CSM_User__c,
                    config.Maximum_Capacity__c.intValue()
                );
            }
        }

        Set<Id> userIds = capacities.keySet();
        Map<Id, Integer> workloads = new Map<Id, Integer>();

        for (Id userId : userIds) {
            workloads.put(userId, 0);
        }

        if (!userIds.isEmpty()) {
            for (AggregateResult result : [
                SELECT OwnerId csmId, COUNT(Id) activeCount
                FROM Onboarding__c
                WHERE OwnerId IN :userIds
                  AND Stage__c != 'Post-Launch Review'
                GROUP BY OwnerId
            ]) {
                workloads.put(
                    (Id) result.get('csmId'),
                    (Integer) result.get('activeCount')
                );
            }
        }

        // Stable tie-breaker when two CSMs have equal workloads.
        List<Id> sortedUserIds = new List<Id>(userIds);
        sortedUserIds.sort();

        List<Group> backlogQueues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
              AND DeveloperName = 'Onboarding_Backlog'
            LIMIT 1
        ];

        for (Onboarding__c onboarding : onboardings) {
            Id selectedUser;
            Integer lowestWorkload;

            for (Id userId : sortedUserIds) {
                Integer workload = workloads.get(userId);

                if (
                    workload < capacities.get(userId) &&
                    (selectedUser == null || workload < lowestWorkload)
                ) {
                    selectedUser = userId;
                    lowestWorkload = workload;
                }
            }

            if (selectedUser != null) {
                onboarding.OwnerId = selectedUser;

                workloads.put(
                    selectedUser,
                    workloads.get(selectedUser) + 1
                );
            } else if (!backlogQueues.isEmpty()) {
                onboarding.OwnerId = backlogQueues[0].Id;
            } else {
                onboarding.addError(
                    'The Onboarding Backlog queue is missing. ' +
                    'Ask your administrator to configure it.'
                );
            }
        }
    }
}