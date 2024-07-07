public with sharing class OpportunityTriggerHandler extends TriggerHandler {
    private List<Opportunity> newOppList;
    private Map<Id, Opportunity> newOpportunityMap;
    private Map<Id, Opportunity> oldOppMap;
    private List<Opportunity> oldOpp;

    public OpportunityTriggerHandler() {
        this.newOppList = (List<Opportunity>)Trigger.new;
        this.oldOppMap =(Map<Id, Opportunity>)Trigger.oldMap;
        this.newOpportunityMap =(Map<Id, Opportunity>)Trigger.newMap;
        this.oldOpp =(List<Opportunity>)Trigger.old;
    }

    public override void beforeUpdate() {
        System.debug('OpportunityTrigger before update');
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity opp : this.newOppList){
            if(opp.Amount < 5000){
                opp.addError('Opportunity amount must be greater than 5000');
            }
            Opportunity oldOpp = this.oldOppMap.get(opp.Id);
            if (oldOpp != null && oldOpp.StageName != opp.StageName){
            opp.Description += '\n Stage Change:' + opp.StageName + ':' + DateTime.now().format();
            }
            //Get contacts related to the opportunity account
            accountIds.add(opp.AccountId);
            }
        
            Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id, FirstName, AccountId FROM Contact WHERE AccountId IN :accountIds AND Title = 'CEO' ORDER BY FirstName ASC]);
            Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();

                for (Contact cont : contacts.values()) {
                     if (!accountIdToContact.containsKey(cont.AccountId)) {
                        accountIdToContact.put(cont.AccountId, cont);
                     }
                }

                for(Opportunity opp : this.newOppList){
             if(opp.Primary_Contact__c == null){
                 if (accountIdToContact.containsKey(opp.AccountId)){
                     opp.Primary_Contact__c = accountIdToContact.get(opp.AccountId).Id;
                 }
             }
         }             
        }
    public override void beforeInsert() {
        //Set default Type for new Opportunities
            for (Opportunity opp : this.newOppList){
                if (opp.Type == null){
                   opp.Type = 'New Customer';
                }
        }
    }
    public override void afterInsert() {
            // Create a new Task for newly inserted Opportunities
              List<Task> taskToInsert = new List<Task>();
              for (Opportunity opp : this.newOppList){
                  Task tsk = new Task();
                  tsk.Subject = 'Call Primary Contact';
                  tsk.WhatId = opp.Id;
                  tsk.WhoId = opp.Primary_Contact__c;
                  tsk.OwnerId = opp.OwnerId;
                  tsk.ActivityDate = Date.today().addDays(3);
                  taskToInsert.add(tsk);
              
        }
    insert taskToInsert;
    }

    public override void beforeDelete() {
        System.debug('OpportunityTrigger before Delete');
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id, Industry FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Id IN :this.oldOpp)]);
      for(Opportunity opp : this.oldOpp){
            if(opp.IsClosed){
                     opp.addError('Cannot delete closed opportunity');
                 }
             }
    }
    
    public override void afterDelete() {
        notifyOwnersOpportunityDeleted(this.oldOpp);
    }

    public override void afterUndelete() {
        assignPrimaryContact(this.newOpportunityMap);
    }

    /*
    notifyOwnersOpportunityDeleted:
    - Sends an email notification to the owner of the Opportunity when it gets deleted.
    - Uses Salesforce's Messaging.SingleEmailMessage to send the email.
    */
    private static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
         Set<Id> ownerIds = new set<Id>();
         for (Opportunity currOpp : opps){
              ownerIds.add(currOpp.OwnerId);
     	}
         Map<Id, User> userMap = new Map<Id, User>([SELECT Id, Email FROM User WHERE ID IN :ownerIds]);
         List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
         for (Opportunity opp : opps){
             User owner = userMap.get(opp.OwnerId);
             if (owner != null && owner.email != null) {
             Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
             String[] toAddresses = new String[] {owner.Email};
             mail.setToAddresses(toAddresses);
             mail.setSubject('Opportunity Deleted : ' + opp.Name);
             mail.setPlainTextBody('Your Opportunity: ' + opp.Name +' has been deleted.');
             mails.add(mail);
             }
         }        
        
        try {
             Messaging.sendEmail(mails);
         } catch (Exception e){
             System.debug('Exception: ' + e.getMessage());
         }
     }
     /*
    assignPrimaryContact:
    - Assigns a primary contact with the title of 'VP Sales' to undeleted Opportunities.
    - Only updates the Opportunities that don't already have a primary contact.
    */
     private static void assignPrimaryContact(Map<Id, Opportunity> oppNewMap) {    
         Set<Id> accountIds = new Set<Id>();
         for (Opportunity currOpp : oppNewMap.values()){
              if (currOpp.AccountId != null){
              accountIds.add(currOpp.AccountId);
              }
         }
         Map<Id, Account> accToConMap = new Map<Id, Account>([SELECT Id, Name, (SELECT Id FROM CONTACTS WHERE Title = 'VP Sales') FROM ACCOUNT WHERE ID IN :accountIds]);    
         Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();
         for (Opportunity opp : oppNewMap.values()){            
            if (opp.Primary_Contact__c == null) {
                Account acc = accToConMap.get(opp.AccountId);
                if (!acc.Contacts.isEmpty()) {
                    Opportunity oppToUpdate = new Opportunity(Id = opp.Id);
                    oppToUpdate.Primary_Contact__c = acc.Contacts[0].Id;
                    oppMap.put(opp.Id, oppToUpdate);
                }
            }
        }
        if (!oppMap.isEmpty()) {
            update oppMap.values();
     }
   }
}