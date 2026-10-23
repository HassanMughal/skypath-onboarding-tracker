trigger OpportunityOnboardingTrigger on Opportunity (
    after insert,
    after update
) {
    OpportunityOnboardingHandler.afterSave(
        Trigger.new,
        Trigger.isUpdate ? Trigger.oldMap : null
    );
}