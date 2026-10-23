trigger OnboardingTrigger on Onboarding__c (
    before insert,
    before update,
    after insert
) {
    if (Trigger.isBefore) {
        OnboardingTriggerHandler.beforeSave(
            Trigger.new,
            Trigger.isUpdate ? Trigger.oldMap : null
        );
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        OnboardingNotificationService.notifyBacklog(Trigger.new);
    }
}