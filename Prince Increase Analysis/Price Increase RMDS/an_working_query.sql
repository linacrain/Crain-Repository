/*Base Advantage Query for AN*/
with advantage_list_uncleaned as (
select
    Expire.ShipToCustomerNumber,
    Expire.DonorType,
    Expire.BillToCustomerNumber,
    BillTo.EmailAddress,
    BillTo.CompanyName,
    case when Expire.OwningOrganizaion like '%AN%' then 'ANG'
     else Expire.OwningOrganizaion
    end as OwningOffice,
    case when Expire.PublicationCode like '%AN1%' then 'Premium'
     when Expire.PublicationCode ='AN2' then 'Basic Digital'
     when Expire.PublicationCode like '%AN3%' then 'AN3'
     when Expire.PublicationCode like '%AN4%' then 'All Access'
    end as publicationcode,
    expire.publicationcode AS pubcheck,
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
    Renewal.TotalLiability RenewalTotalPrice,
    case when Expire.PublicationCode like '%AN3%' then 3
      when Expire.PublicationCode like '%AN1%' then 2
      when Expire.PublicationCode ='AN2' then 1
      when expire.publicationcode like '%AN4%' then 4
    end as pub_level
from prod.reporting.AdvantageSubscriptionTerms Expire
LEFT join prod.reporting.advantage_subscription Sub on Sub.SubscriptionReference = Expire.SubscriptionReference
left join prod.reporting.AdvantageSubscriptionTerms Renewal on Renewal.SubscriptionReference = Expire.SubscriptionReference and Renewal.TermNumber = Expire.TermNumber + 1
left join prod.reporting.advantage_customer BillTo on BillTo.CustomerNumber = Expire.BillToCustomerNumber and BillTo.AddressCode = Expire.BillToAddressCode
where expire.OwningOrganizaion='AN'),


/*Rolling up invoices based on whether they are a liability or they have a new subscription cycle*/
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


/*CNY Individual Existing Users*/
AN_I as (
SELECT distinct
	cast(regexp_replace(s.oldproviderid,'[^0-9]','') as float) as adv_sub_id,
	case when i.susbcriptionid is null then s.subscriptionid
		else i.susbcriptionid end as subscriptionid,
	i.invoiceid as ordernumber,
		case when i.customeraccountid is null then s.customeraccountid
		else i.customeraccountid end as customeraccountid,
	case when ps.planinterval like '%year%' then 'Annual'
		 when ps.planinterval like '%month%' then 'Monthly'
		 when ps.planinterval is null and isannualterm=true then 'Annual'
		 when ps.planinterval is null and ismonthlyterm=true then 'Monthly'
	else 'day' end as termlength,
	case when ps.isautorenew is null then 'N'
		else 'Y'
	end as isautorenew,
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
	case when i.subscriptioncurrentperiodstartdatetime is not null then i.subscriptioncurrentperiodstartdatetime 
		 when i.subscriptioncurrentperiodstartdatetime is null then s.currentperiodstartdatetime end as start_date,
	case when i.subscriptioncurrentperiodenddatetime is not null then i.subscriptioncurrentperiodenddatetime 
		 when i.subscriptioncurrentperiodenddatetime is null then s.currentperiodenddatetime end as expire_date,
	case when i.planamount is not null then i.planamount
		else price end AS rate,
	i.planid as planid,
	i.chargereferences,
	i.amountpaid as amountpaid,
	i.paidatdatetime as orderdate
FROM prod.pelcro.subscription s
left join rolled_up_invoice i on i.susbcriptionid = s.subscriptionid
left join prod.pelcro.subscription_plan ps on ps.planid=i.planid
where s.businessunitcode = 'ANG'
	and s.ispaid is true
	and oldproviderid is not null
order by currentperiodenddatetime
),
	
adv_pelcro_index as (
select distinct 
	a.shiptocustomernumber,
	a.ordernumber,
	c.subscriptionid,
	c.adv_sub_id
from advantage_list_uncleaned a 
join an_i c on c.adv_sub_id=a.subscriptionreference),

	
advantage_list as (
select 
	a.shiptocustomernumber,
	a.owningoffice,
	a.ordernumber,
	a.publicationcode,
	a.subscriptionreference,
	p.subscriptionid as pelcro_subid,
	a.termnumber,
	a.isautorenew,
	a.termlength,
	a.renewalordernumber,
	a.renewalstartdate,
	a.startissuedate,
	a.expirationissuedate,
	a.rate,
	a.renewalrate,
	a.donortype,
	p.subscriptionid,
	a.pub_level,
	case when pelcro_subid is not null then subscriptionreference
	else null::numeric end as pelcro_sub_agg,
	p.adv_sub_id,
	a.orderdate::date
	
from advantage_list_uncleaned a 
LEFT join adv_pelcro_index p on p.shiptocustomernumber=a.shiptocustomernumber and p.ordernumber=a.ordernumber and adv_sub_id=a.subscriptionreference),




linked_row_agg_info as (
select 
	shiptocustomernumber,
	owningoffice,
	ordernumber,
	case when max(pub_level)=4 then 'All Access'
		 when max(pub_level)=3 then 'AN3'
	   	 when max(pub_level)=2 then 'Premium'
	   	 when max(pub_level)=1 then 'Basic Digital'
	   	 when max(pub_level)=0 then 'Premium Canada'
	end as publicationcode,
	max(termnumber) as termnumber,
	sum(rate) as rate,
	sum(renewalrate) as renewalrate
from advantage_list
group by shiptocustomernumber,owningoffice,ordernumber
),


linked_row_non_agg_info as (
select shiptocustomernumber,
	   subscriptionreference,
	   pelcro_subid,
	   owningoffice,
	   ordernumber,
	   orderdate,
	   isautorenew,
	   termlength,
	   startissuedate,
	   expirationissuedate,
	   renewalordernumber,
	   renewalstartdate,
	   renewalrate,
	   donortype
	   
from advantage_list
where adv_sub_id= subscriptionreference
),

linked_adv_rows as (
select agg.shiptocustomernumber,
	   agg.owningoffice,
	   agg.ordernumber,
	   na.orderdate,
	   agg.publicationcode,
	   na.subscriptionreference,
	   na.pelcro_subid,
	   agg.termnumber,
	   na.isautorenew,
	   na.termlength,
	   na.startissuedate,
	   na.expirationissuedate,
	   agg.rate,
	   na.renewalordernumber,
	   na.renewalstartdate,
	   agg.renewalrate,
	   na.donortype
from linked_row_agg_info agg
join linked_row_non_agg_info na on na.shiptocustomernumber=agg.shiptocustomernumber and na.ordernumber=agg.ordernumber
),





non_linked_adv_index as (
select distinct
	al.*
from advantage_list al
left join linked_adv_rows flar on flar.shiptocustomernumber=al.shiptocustomernumber and flar.ordernumber=al.ordernumber
where flar.shiptocustomernumber is null and flar.ordernumber is null
),

non_linked_roll_up as (
select 
	shiptocustomernumber,
	owningoffice,
	ordernumber,
	case when max(pub_level)=4 then 'All Access'
		 when max(pub_level)=3 then 'AN3'
	   	 when max(pub_level)=2 then 'Premium'
	   	 when max(pub_level)=1 then 'Basic Digital'
	   	 when max(pub_level)=0 then 'Premium Canada'
	end as publicationcode,
	max(termnumber) as termnumber,
	sum(rate) as rate,
	sum(renewalrate) as renewalrate
from non_linked_adv_index
group by shiptocustomernumber,owningoffice,ordernumber
),


non_linked_agg_info as (
select nlru.shiptocustomernumber,
	   nlru.owningoffice,
	   nlru.ordernumber,
	   nlai.orderdate,
	   nlai.publicationcode,
	   nlai.subscriptionreference,
	   nlai.pelcro_subid,
	   nlru.termnumber,
	   nlai.isautorenew,
	   nlai.termlength,
	   nlai.startissuedate,
	   nlai.expirationissuedate,
	   nlru.rate,
	   nlai.renewalordernumber,
	   nlai.renewalstartdate,
	   nlru.renewalrate,
	   nlai.donortype 
from non_linked_roll_up nlru left join non_linked_adv_index nlai on nlai.shiptocustomernumber=nlru.shiptocustomernumber and nlai.ordernumber=nlru.ordernumber and  nlai.publicationcode=nlru.publicationcode
),


advantage_list_full as (
select * from linked_adv_rows
union
select * from non_linked_agg_info
),




non_linked_adv_rows as (
select 
	a.shiptocustomernumber::varchar as shiptocustomernumber,
	a.shiptocustomernumber::numeric as original_adv_cust_value,
	a.ordernumber as ordernumber,
	a.orderdate,
	a.owningoffice as brand,
	a.publicationcode as pubcode,
	a.subscriptionreference as adv_subid,
	a.pelcro_subid,
	a.termnumber,
	a.isautorenew,
	a.startissuedate,
	a.expirationissuedate,
	a.rate,
	a.rate as amountpaid,
	a.termlength,
	a.renewalordernumber::varchar,
	a.renewalstartdate::date,
	a.renewalrate::varchar,
	a.donortype
from (select 
		*
	  from advantage_list_full a 
	  where pelcro_subid is null) a
order by shiptocustomernumber,pubcode,startissuedate
),
/*Advantage Records up to last renewal before migration*/
adv_pelcro_link as (
select distinct 
	c.customeraccountid as shiptocustomernumber,
	cast(a.shiptocustomernumber as numeric) as original_adv_cust_value,
	a.ordernumber as ordernumber,
	a.orderdate,
	a.owningoffice as brand,
	a.publicationcode as pubcode,
	a.subscriptionreference as adv_subid,
	a.pelcro_subid,
	a.termnumber,
	a.isautorenew,
	a.startissuedate,
	a.expirationissuedate,
	a.rate,
	a.rate as amountpaid,
	a.termlength,
	a.renewalordernumber::varchar,
	a.renewalstartdate::date,
	a.renewalrate::varchar,
	a.donortype
from (SELECT
		*
	  FROM advantage_list_full
	  WHERE pelcro_subid IS NOT null) a join an_i c on c.subscriptionid=a.pelcro_subid
where renewalstartdate is not null
order by shiptocustomernumber,pubcode,startissuedate
),

rolled_up_an as (
SELECT 
    subscriptionid, 
    start_date,
    expire_date,
    max(totalprice) as totalprice
 FROM an_i
 GROUP BY subscriptionid,start_date,expire_date
),


/*Renewal Record Row: Will insert Pelcro Sub if the last contract ended before migration. Otherwise, the original Adv row with updated amount 
 * paid and expiration date from pelcro will be used */
renewal_row_no_in_between as (
select distinct 
	c.customeraccountid as shiptocustomernumber,
	cast(a.shiptocustomernumber as numeric) as original_adv_cust_value,
	a.ordernumber as ordernumber,
	a.orderdate,
	a.owningoffice as brand,
	case when (c.start_date>=startissuedate and c.start_date<=expirationissuedate and c.expire_date=a.expirationissuedate) then c.publicationcode
	  else a.publicationcode 
	end as pubcode,
	a.subscriptionreference as adv_subid,
	a.pelcro_subid,
	a.termnumber,
	a.isautorenew,
	a.startissuedate,
	c.start_date,
	c.chargereferences,
	a.expirationissuedate,
	a.rate,
	case when (c.chargereferences like '%Liability%') then c.amountpaid
	  else a.rate 
	end as amountpaid,
	a.termlength,
	case when (c.chargereferences like '%Liability%') or (expire_date::date=expirationissuedate) then a.renewalordernumber::varchar
	  else c.ordernumber::varchar 
	end as renewalordernumber,
	case when (c.chargereferences like '%Liability%') or (expire_date::date=expirationissuedate) then a.renewalstartdate::date
	  else c.start_date::date 
	end as renewalstartdate,
	case when (c.chargereferences like '%Liability%') or (expire_date::date=expirationissuedate) then a.renewalrate::varchar
	  else c.rate::varchar 
	end as renewalrate,
	a.donortype
from (select * from advantage_list_full where renewalstartdate is null) a 
join (SELECT 
		ci.*
	  FROM an_i ci
	  join rolled_up_an ruc on ruc.subscriptionid=ci.subscriptionid and ruc.totalprice=ci.totalprice) c on c.subscriptionid=a.pelcro_subid
where (c.start_date=expirationissuedate or c.start_date>startissuedate) or (c.start_date>=startissuedate and c.start_date<=expirationissuedate) or (expirationissuedate=expire_date) or (expirationissuedate=expire_date) or c.chargereferences is null or c.chargereferences like '%null%' or c.chargereferences is not null
),

min_start_date as (
select shiptocustomernumber,ordernumber,pelcro_subid,adv_subid,min(renewalstartdate) as min_date from renewal_row_no_in_between group by shiptocustomernumber,ordernumber,pelcro_subid,adv_subid
having count(*)>1),



union_renewal_row as (
select r.* from renewal_row_no_in_between r 
join min_start_date msd on msd.min_date=r.renewalstartdate

union 

select r.* from renewal_row_no_in_between r where not exists
(select shiptocustomernumber,ordernumber,pelcro_subid,adv_subid from min_start_date)
)

select * from union_renewal_row
