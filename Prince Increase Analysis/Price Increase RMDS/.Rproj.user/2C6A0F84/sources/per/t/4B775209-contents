with 
advantage_list_uncleaned as (
select
    Expire.ShipToCustomerNumber,
    Expire.DonorType,
    Expire.BillToCustomerNumber,
    BillTo.EmailAddress,
    BillTo.CompanyName,
    Expire.OwningOrganizaion as OwningOffice,
    Expire.PublicationCode as publicationcode,
    Expire.PromotionCode,
    Expire.SubscriptionReference,
    Sub.FirstIssueSent,
    Expire.TermNumber,
    Expire.OriginalOrderNumber OrderNumber,
    Expire.OriginalControlGroupDate OrderDate,
    Expire.StartIssueDate,
    Expire.ExpirationIssueDate,
    Expire.CirculationStatus,
    Expire.BillingCurrency,
    Expire.Rate,
    case when Expire.TermLength<8 then 'Monthly'
      else 'Annual' end as termlength,
     expire.termlength as og_termlength,
    Expire.Copies,
    Expire.TotalLiability TotalPrice,
    Sub.RenewalPolicy,
    case when Sub.RenewalPolicy in ('A','C') then 'Y' 
      else 'N' 
    end IsAutoRenew,
    Renewal.TermNumber RenewalTermNumber,
    Renewal.OriginalOrderNumber RenewalOrderNumber,
    Renewal.PromotionCode RenewalPromotionCode,
    Renewal.OriginalControlGroupDate RenewalOrderDate,
    Renewal.StartIssueDate RenewalStartDate,
    Renewal.CirculationStatus RenewalCirculationStatus,
    Renewal.BillingCurrency RenewalBillingCurrency,
    Renewal.Rate RenewalRate,
    Renewal.TermLength RenewalTermLength,
    Renewal.Copies RenewalCopies,
    Renewal.TotalLiability RenewalTotalPrice
from prod.reporting.AdvantageSubscriptionTerms Expire
LEFT join prod.reporting.advantage_subscription Sub on Sub.SubscriptionReference = Expire.SubscriptionReference
left join prod.reporting.AdvantageSubscriptionTerms Renewal on Renewal.SubscriptionReference = Expire.SubscriptionReference and Renewal.TermNumber = Expire.TermNumber + 1
left join prod.reporting.advantage_customer BillTo on BillTo.CustomerNumber = Expire.BillToCustomerNumber and BillTo.AddressCode = Expire.BillToAddressCode
where expire.OwningOrganizaion='CCB'),





reduced_invoice as (
select 
	*,
	case when chargereferences like '%Liability%' then 0
	  else 1 
	end as charge_value,
	case when subscriptioncurrentperiodstartdatetime is null and subscriptioncurrentperiodenddatetime is null then 0 
	else 1 
	end as sub_length_value
from prod.pelcro.invoice 
where invoicetotal is not null),

max_charge as (
select 
	susbcriptionid,
	max(charge_value) as max_charge,
	max(sub_length_value) as max_sub_length
from reduced_invoice 
group by susbcriptionid),

rolled_up_invoice as (
select 
	r.* 
from reduced_invoice r 
join max_charge m on m.susbcriptionid=r.susbcriptionid and m.max_charge=r.charge_value and m.max_sub_length=r.sub_length_value),





/*CCB Individual Existing Users*/
ccb_I_t as (
SELECT distinct
		substring(s.metadata,position('"crainchicago_' in s.metadata)+14,position('"common_is_future' in s.metadata)-position('"crainchicago_' in s.metadata)) as test,
    substring(test,1,12) as adv_sub_id
    ,position('"common_is_future' in s.metadata),
    substring(s.metadata,position('common_order_number":"' in s.metadata)+22,position(',"common_order_term' in s.metadata)-position('common_order_number":"' in s.metadata)) as test2,
    substring(test2,1,8) as adv_order_number,
	case when i.susbcriptionid is null then s.subscriptionid
		else i.susbcriptionid end as subscriptionid,
	i.invoiceid as ordernumber,
		case when i.customeraccountid is null then s.customeraccountid
		else i.customeraccountid end as customeraccountid,
	case when i.businessunitcode is null then s.businessunitcode
		else i.businessunitcode end as brand,
	case when i.amountdue is null then s.planamount 
		else i.amountdue end as totalprice,
	case when i.planproductname is not null then i.planproductname 
		else s.productname end as publicationcode,
	case when s.iscorporate=TRUE then 'B'
	  when s.isagency=TRUE then 'A'
	  when s.iscomp=TRUE then 'C'
	  when s.isgiftdonor then 'D'
	  when s.isindividual=TRUE then 'I'
	  else 'G' 
	end as donortype,
	isannualterm,
	ismonthlyterm,
	case when i.subscriptioncurrentperiodstartdatetime is not null then i.subscriptioncurrentperiodstartdatetime 
		 when i.subscriptioncurrentperiodstartdatetime is null then s.currentperiodstartdatetime end as start_date,
	case when i.subscriptioncurrentperiodenddatetime is not null then i.subscriptioncurrentperiodenddatetime 
		 when i.subscriptioncurrentperiodenddatetime is null then s.currentperiodenddatetime end as expire_date,
	case when i.planamount is not null then i.planamount
		else price end AS rate,
	case when i.planid is null then s.planid
	else i.planid
	end as planid,
	i.amountpaid as amountpaid,
	case when i.billingtype like '%charge%' then 'Y'
		else 'N'
	end as isautorenew,
	i.paidatdatetime as orderdate,
	i.chargereferences,
	s.iscorporate,
	s.isagency,
	s.iscomp,
	s.isgiftdonor,
	s.isindividual
FROM prod.pelcro.subscription s
left join rolled_up_invoice i on i.susbcriptionid = s.subscriptionid
where s.businessunitcode = 'CCB'
	and s.ispaid is true
	and s.isindividual is true
	and s.issourced is true
order by currentperiodenddatetime
),

ccb_i as (

select case when adv_sub_id='' then NULL::numeric
       else adv_sub_id::numeric end as adv_sub_id,
adv_order_number,
subscriptionid,
ordernumber,
customeraccountid,
brand,
totalprice,
publicationcode,
donortype,
start_date,
expire_date,
rate,
amountpaid,
c.isautorenew,
orderdate,
case when ps.planinterval like '%year%' then 'Annual'
		 when ps.planinterval like '%month%' then 'Monthly'
		 when ps.planinterval is null and isannualterm=true then 'Annual'
		 when ps.planinterval is null and ismonthlyterm=true then 'Monthly'
	else 'day' end as termlength,
c.chargereferences,
c.iscorporate,
	c.isindividual,
	c.isagency,
	c.iscomp,
	c.isgiftdonor
from ccb_i_t c
left join prod.pelcro.subscription_plan ps on ps.planid=c.planid),

advantage_list_



select * from ccb_i