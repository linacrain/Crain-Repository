select distinct 
  Expire.ShipToCustomerNumber::varchar
    , Expire.ShipToCustomerNumber::numeric as original_adv_cust_value
    , Expire.OriginalOrderNumber::varchar OrderNumber
    , Expire.OriginalControlGroupDate::varchar OrderDate
    , Expire.OwningOrganizaion::varchar brand
    , Expire.PublicationCode::varchar
    , Expire.SubscriptionReference::numeric adv_subid
    , Expire.copies
    , NULL::numeric as pelcro_subid
    , Expire.TermNumber::numeric
    , case when Sub.RenewalPolicy in ('A','C') then 'Y' else 'N' end IsAutoRenew
    , Expire.StartIssueDate::date
    , Expire.ExpirationIssueDate::date
    , Expire.Rate::numeric
    , Expire.TermLength::varchar
    , Renewal.OriginalOrderNumber::varchar RenewalOrderNumber
    , Renewal.Rate::numeric RenewalRate
    , Renewal.StartIssueDate::date RenewalStartDate
    , Expire.DonorType::varchar
    , Expire.TermType 
    , Expire.SubscriptionClass
from prod.reporting.AdvantageSubscriptionTerms Expire
left join prod.reporting.advantage_subscription Sub on Sub.SubscriptionReference = Expire.SubscriptionReference
left join prod.reporting.AdvantageSubscriptionTerms Renewal on Renewal.SubscriptionReference = Expire.SubscriptionReference and Renewal.TermNumber = Expire.TermNumber + 1
left join prod.reporting.advantage_customer BillTo on BillTo.CustomerNumber = Expire.BillToCustomerNumber and BillTo.AddressCode = Expire.BillToAddressCode
where expire.OwningOrganizaion in ('CL','CB','CD','CN')