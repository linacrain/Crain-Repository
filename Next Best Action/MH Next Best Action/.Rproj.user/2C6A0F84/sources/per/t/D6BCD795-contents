select
      Expire.ShipToCustomerNumber
    , Expire.DonorType
    , Expire.BillToCustomerNumber
    , BillTo.EmailAddress
    , BillTo.CompanyName
    , Expire.OwningOrganizaion OwningOffice
    , Expire.PublicationCode
    , Expire.PromotionCode
    , Expire.SubscriptionReference
    , Sub.FirstIssueSent
    , Expire.TermNumber
    , Expire.OriginalOrderNumber OrderNumber
    , Expire.OriginalControlGroupDate OrderDate
    , Expire.StartIssueDate
    , Expire.ExpirationIssueDate
    , Expire.CirculationStatus
    , Expire.BillingCurrency
    , Expire.Rate
    , Expire.TermLength
    , Expire.Copies
    , Expire.TotalLiability TotalPrice
    , Sub.RenewalPolicy
    , case when Sub.RenewalPolicy in ('A','C') then 'Y' else 'N' end IsAutoRenew
    , Renewal.TermNumber RenewalTermNumber
    , Renewal.OriginalOrderNumber RenewalOrderNumber
    , Renewal.PromotionCode RenewalPromotionCode
    , Renewal.OriginalControlGroupDate RenewalOrderDate
    , Renewal.StartIssueDate RenewalStartDate
    , Renewal.CirculationStatus RenewalCirculationStatus
    , Renewal.BillingCurrency RenewalBillingCurrency
    , Renewal.Rate RenewalRate
    , Renewal.TermLength RenewalTermLength
    , Renewal.Copies RenewalCopies
    , Renewal.TotalLiability RenewalTotalPrice
from reporting.AdvantageSubscriptionTerms Expire
left join reporting.advantage_subscription Sub on Sub.SubscriptionReference = Expire.SubscriptionReference
left join reporting.AdvantageSubscriptionTerms Renewal on Renewal.SubscriptionReference = Expire.SubscriptionReference and Renewal.TermNumber = Expire.TermNumber + 1
left join reporting.advantage_customer BillTo on BillTo.CustomerNumber = Expire.BillToCustomerNumber and BillTo.AddressCode = Expire.BillToAddressCode
and Expire.ExpirationIssueDate >= '2016-01-01'
and Expire.OwningOrganizaion='MH'