with advantage_list_uncleaned as (
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
    Renewal.TotalLiability RenewalTotalPrice,
    case when expire.publicationcode = 'CB1' then 1
         when expire.publicationcode = 'CB2' then 2
         when expire.publicationcode = 'CB3' then 3
         when expire.publicationcode = 'CBH' then 4
    end as pub_level
from prod.reporting.AdvantageSubscriptionTerms Expire
LEFT join prod.reporting.advantage_subscription Sub on Sub.SubscriptionReference = Expire.SubscriptionReference
left join prod.reporting.AdvantageSubscriptionTerms Renewal on Renewal.SubscriptionReference = Expire.SubscriptionReference and Renewal.TermNumber = Expire.TermNumber + 1
left join prod.reporting.advantage_customer BillTo on BillTo.CustomerNumber = Expire.BillToCustomerNumber and BillTo.AddressCode = Expire.BillToAddressCode
where expire.OwningOrganizaion='CCB' and expire.donortype='I'
),
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

adv_pelcro_index as (
select distinct 
	a.shiptocustomernumber,
	a.ordernumber,
	c.subscriptionid,
	c.adv_sub_id
from advantage_list_uncleaned a 
join ccb_i c on c.adv_sub_id=a.subscriptionreference),
	
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
	case when max(pub_level)=4 then 'CBH'
	   	 when max(pub_level)=3 then 'CB3'
	   	 when max(pub_level)=2 then 'CB2'
	   	 when max(pub_level)=1 then 'CB1'
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
	case when max(pub_level)=4 then 'CBH'
		 when max(pub_level)=3 then 'CB3'
	   	 when max(pub_level)=2 then 'CB2'
	   	 when max(pub_level)=1 then 'CB1'
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
	  WHERE pelcro_subid IS NOT null) a join ccb_i c on c.subscriptionid=a.pelcro_subid
where renewalstartdate is not null
order by shiptocustomernumber,pubcode,startissuedate
),

rolled_up_ccb as (
SELECT 
    subscriptionid, 
    MIN(start_date) as start_date
 FROM ccb_i
 where ccb_i.adv_sub_id is not null
 GROUP BY subscriptionid
),

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
	  FROM ccb_i ci
	  join rolled_up_ccb ruc on ruc.subscriptionid=ci.subscriptionid and ruc.start_date=ci.start_date) c on c.subscriptionid=a.pelcro_subid
where c.ordernumber=a.ordernumber or c.chargereferences is null or c.chargereferences like '%null%' or c.chargereferences is not null
),

max_renewal_row_term_number as (
select 
	pelcro_subid, 
	max(termnumber) as last_adv_term_value 
from renewal_row_no_in_between 
group by pelcro_subid
),

union_temp as (
SELECT
	*
FROM non_linked_adv_rows

union


select 
	* 
from adv_pelcro_link

union 

select 
	* 
from renewal_row_no_in_between),



/*Generating the Term Number*/
adv_layer_data as (
select 
	original_adv_cust_value,
	pelcro_subid,
	ordernumber,
	max(expirationissuedate) as last_expiration_date,
	max(termnumber) as last_adv_term_value 
from union_temp
group by original_adv_cust_value,pelcro_subid,ordernumber
),

/*Reorganizing the Pelcro Rows to be in the same format as Advantage*/
pelcro_layers as (
select distinct 
	c.customeraccountid::varchar as shiptocustomernumber,
	r.original_adv_cust_value::numeric as original_adv_cust_value,
	cast(c.ordernumber as varchar),
	c.orderdate,
	c.brand,
	c.publicationcode as pubcode,
	c.subscriptionid as subid,
	c.subscriptionid as pelcro_subid,
	r.last_adv_term_value + row_number() over (partition by c.customeraccountid,c.subscriptionid order by c.start_date) as termnumber,
	c.isautorenew,
	c.start_date as startissuedate,
	c.expire_date as expirationissuedate,
	c.rate,
	c.amountpaid,
	case when c.termlength is null and extract(day from (expirationissuedate-startissuedate))<=31 then 'Monthly'
		 when c.termlength is null and extract(day from (expirationissuedate-startissuedate))>=300 then 'Annual'
		 when c.termlength is not null then c.termlength end as termlength,
	cast(lead(c.ordernumber) over (partition by c.customeraccountid,c.subscriptionid order by c.start_date)as varchar) as renewalordernumber,
	lead(start_date) over (partition by c.customeraccountid,c.subscriptionid order by c.start_date)::date as renewalstartdate,
	lead(c.rate) over (partition by c.customeraccountid,c.subscriptionid order by c.start_date)::varchar as renewalrate,
	c.donortype
from (select * from ccb_i c where adv_sub_id is not null) c
left join adv_layer_data r on r.pelcro_subid=c.subscriptionid
where c.expire_date>r.last_expiration_date
  and c.ordernumber!=r.ordernumber
),

new_cust as (
select distinct
	s.customeraccountid::varchar as shiptocustomernumber,
	null::numeric as original_adv_cust_value,
	case when sp.planinterval='month' then cast(s.subscriptionid as varchar)+i.invoiceid
	  else cast(i.invoiceid as varchar) 
	end as ordernumber,
	i.paidatdatetime as orderdate,
	i.businessunitcode as brand, 
	i.planproductname as pubcode,
	null::numeric as adv_subid,
	i.susbcriptionid::numeric as pelcro_subid,
	dense_rank() over (partition by i.susbcriptionid order by startissuedate) as termnumber,
	case when sp.isautorenew is null then 'N'
		else 'Y'
	end as isautorenew,
	case when i.subscriptioncurrentperiodstartdatetime is null then subscriptionstartdatetime
	  else subscriptioncurrentperiodstartdatetime 
	end as startissuedate,
	i.subscriptioncurrentperiodenddatetime as expirationissuedate,
	i.amountdue AS rate,
	i.amountpaid,
	case when sp.planinterval like '%year%' then 'Annual'
 	  when sp.planinterval like '%month%' then 'Monthly'
 	  when sp.planinterval like '%day%' then 'Day'
	  when extract(day from (expirationissuedate-startissuedate))<=31 then 'Monthly'
	  when extract(day from (expirationissuedate-startissuedate))>=300 then 'Annual' 
	end as termlength,
	lead(ordernumber) over (partition by pelcro_subid order by startissuedate)::varchar as renewalordernumber,
	lead(startissuedate) over (partition by pelcro_subid order by startissuedate) as renewalstartdate,
	lead(i.amountdue) over (partition by pelcro_subid order by startissuedate)::varchar as renewalrate,
	case when s.iscorporate=TRUE then 'B'
	  when s.isagency=TRUE then 'A'
	  when s.iscomp=TRUE then 'C'
	  when s.isgiftdonor then 'D'
	  when s.isindividual=TRUE then 'I'
	  else 'G' 
	end as donortype
from (select * from ccb_i where adv_sub_id is null) s
left join prod.pelcro.invoice i on i.susbcriptionid = s.subscriptionid 
left join prod.pelcro.subscription_plan sp on sp.planid=i.planid
where i.businessunitcode = 'CCB'
order by pelcro_subid,termnumber),




/*Final Union*/
final_temp as (
select 
	* 
from union_temp

union 

select 
	* 
from pelcro_layers
),

individual_customers as (
select distinct 
	*
from final_temp

union 

select distinct 
	* 
from new_cust)


select distinct
	i.shiptocustomernumber,
	i.original_adv_cust_value,
	i.ordernumber,
	i.orderdate,
	i.brand,
	i.pubcode,
	i.adv_subid,
	i.pelcro_subid,
	i.termnumber,
	i.isautorenew,
	i.startissuedate,
	i.expirationissuedate,
	i.rate,
	i.termlength,
	i.renewalordernumber,
	i.renewalrate,
	i.donortype
	
from individual_customers i
order by i.pelcro_subid,termnumber,i.startissuedate
























