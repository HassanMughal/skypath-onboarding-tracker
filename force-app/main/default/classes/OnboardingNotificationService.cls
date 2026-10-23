public without sharing class OnboardingNotificationService {
    public static void notifyBacklog(List<Onboarding__c> records) {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
              AND DeveloperName = 'Onboarding_Backlog'
            LIMIT 1
        ];

        if (queues.isEmpty()) {
            return;
        }

        Id backlogId = queues[0].Id;
        Integer backlogCount = 0;
        Id firstBacklogRecordId;

        for (Onboarding__c record : records) {
            if (record.OwnerId == backlogId) {
                backlogCount++;

                if (firstBacklogRecordId == null) {
                    firstBacklogRecordId = record.Id;
                }
            }
        }

        if (backlogCount == 0) {
            return;
        }

        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = 'Onboarding_Backlog_Alert'
            LIMIT 1
        ];

        if (notificationTypes.isEmpty()) {
            for (Onboarding__c record : records) {
                if (record.OwnerId == backlogId) {
                    record.addError(
                        'Configure the Onboarding_Backlog_Alert ' +
                        'custom notification type before creating backlog work.'
                    );
                }
            }
            return;
        }

        Messaging.CustomNotification notification =
            new Messaging.CustomNotification();

        notification.setNotificationTypeId(notificationTypes[0].Id);
        notification.setTitle('Onboarding backlog needs attention');
        notification.setBody(
            String.valueOf(backlogCount) +
            ' new onboarding(s) entered the backlog because no eligible ' +
            'CSM had available capacity. Review the queue and assign work.'
        );
        notification.setTargetId(firstBacklogRecordId);

        notification.send(
            new Set<String>{ String.valueOf(backlogId) }
        );
    }
}