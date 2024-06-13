create table dev.pelcro_records.cny as (/*Base Advantage Query for CNY, Individuals Only*/
with advantage_list_uncleaned as (
select
	
    Expire.ShipToCustomerNumber,
    Expire.DonorType,
    Expire.BillToCustomerNumber,
    BillTo.EmailAddress,
    BillTo.CompanyName,
    case when Expire.OwningOrganizaion like '%CN%' then 'CNY'
     else Expire.OwningOrganizaion 
    end as OwningOffice,
    case when Expire.PublicationCode like '%NHF%' then 'Health Pulse'
     when Expire.PublicationCode ='CN' then 'Premium'
     when Expire.PublicationCode like '%CNW%' then 'Basic Digital'
     else 'All Access' 
    end as publicationcode,
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
      when Expire.TermLength>=52 then 'Annual' end as termlength,
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
    case when Expire.PublicationCode like '%CND%' then 4
      when Expire.PublicationCode like '%NHF%' then 3
      when Expire.PublicationCode ='CN' then 2
      when Expire.PublicationCode like '%CNW%' then 1
    end as pub_level,
    case when expire.subscriptionreference=23545740 or
    		  expire.subscriptionreference=25134531 or
    		  expire.subscriptionreference=24943478 or
    		  expire.subscriptionreference=24343617 or
    		  expire.subscriptionreference=23881742 or 
    		  expire.subscriptionreference=24115664 then true 
    	 when Expire.PublicationCode like '%CND%' then true 
    	 else false 
   	end as is_data,
   	case when Expire.PublicationCode like '%NHF%' then true
   		 else false 
   	end as is_health_pulse,
   	case when Expire.PublicationCode='CN' then true 
   		else false
   	end as is_print,
   	case when Expire.PublicationCode='CNW' then true
   		 when Expire.PublicationCode='CN' then true
   		else false
   	end as is_digital
from prod.reporting.AdvantageSubscriptionTerms Expire
join prod.reporting.advantage_subscription Sub on Sub.SubscriptionReference = Expire.SubscriptionReference
left join prod.reporting.AdvantageSubscriptionTerms Renewal on Renewal.SubscriptionReference = Expire.SubscriptionReference and Renewal.TermNumber = Expire.TermNumber + 1
left join prod.reporting.advantage_customer BillTo on BillTo.CustomerNumber = Expire.BillToCustomerNumber and BillTo.AddressCode = Expire.BillToAddressCode
where owningoffice like '%CN%'),
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
CNY_I as (
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
	s.isprint,
	s.isdigital,
	s.ishealthpulse,
	s.isdata,
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
		 when i.subscriptioncurrentperiodstartdatetime is null then s.currentperiodstartdatetime end as expire_date,
	case when i.planamount is not null then i.planamount
		else price end AS rate,
	i.planid as planid,
	i.chargereferences,
	i.amountpaid as amountpaid,
	i.paidatdatetime as orderdate
FROM prod.pelcro.subscription s
left join rolled_up_invoice i on i.susbcriptionid = s.subscriptionid
left join prod.pelcro.subscription_plan ps on ps.planid=i.planid
where s.businessunitcode = 'CNY'
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
join cny_i c on c.adv_sub_id=a.subscriptionreference),
	
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
	a.is_print,
	a.is_health_pulse,
	a.is_digital,
	a.is_data,
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
	   	 when max(pub_level)=2 then 'Premium'
	   	 when max(pub_level)=1 then 'Basic Digital'
	end as publicationcode,
	max(termnumber) as termnumber,
	sum(rate) as rate,
	sum(renewalrate) as renewalrate
from advantage_list
where publicationcode not like '%Health Pulse%'
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
where publicationcode not like '%Health Pulse%' and adv_sub_id= subscriptionreference
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

nhf_rows as (
select al.shiptocustomernumber,
	   al.owningoffice,
	   al.ordernumber,
	   al.orderdate,
	   al.publicationcode,
	   al.subscriptionreference,
	   al.pelcro_subid,
	   al.termnumber,
	   al.isautorenew,
	   al.termlength,
	   al.startissuedate,
	   al.expirationissuedate,
	   al.rate,
	   al.renewalordernumber,
	   al.renewalstartdate,
	   al.renewalrate,
	   al.donortype 
from advantage_list al where adv_sub_id=subscriptionreference and publicationcode like '%Health Pulse%'
),

full_linked_adv_rows as (
select * from nhf_rows
union 
select * from linked_adv_rows ),


non_linked_adv_index as (
select distinct
	al.*
from advantage_list al
left join full_linked_adv_rows flar on flar.shiptocustomernumber=al.shiptocustomernumber and flar.ordernumber=al.ordernumber
where flar.shiptocustomernumber is null and flar.ordernumber is null
),

non_linked_roll_up as (
select 
	shiptocustomernumber,
	owningoffice,
	ordernumber,
	case when max(pub_level)=4 then 'All Access'
		 when max(pub_level)=3 then 'Health Pulse'
	   	 when max(pub_level)=2 then 'Premium'
	   	 when max(pub_level)=1 then 'Basic Digital'
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
select * from full_linked_adv_rows
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
	  WHERE pelcro_subid IS NOT null) a join cny_i c on c.subscriptionid=a.pelcro_subid
where renewalstartdate is not null
order by shiptocustomernumber,pubcode,startissuedate
),








rolled_up_cny as (
SELECT 
    subscriptionid, 
    MIN(start_date) as start_date
 FROM cny_i
 GROUP BY subscriptionid
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
	  FROM cny_i ci
	  join rolled_up_cny ruc on ruc.subscriptionid=ci.subscriptionid and ruc.start_date=ci.start_date) c on c.subscriptionid=a.pelcro_subid
where (c.start_date=expirationissuedate or c.start_date>startissuedate) or (c.start_date>=startissuedate and c.start_date<=expirationissuedate) or (expirationissuedate=expire_date) or c.chargereferences is null or c.chargereferences like '%null%' or c.chargereferences is not null
),

max_renewal_row_term_number as (
select 
	pelcro_subid, 
	max(termnumber) as last_adv_term_value 
from renewal_row_no_in_between 
group by pelcro_subid
),



/*Union from Advantage and Renewal Row*/
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
	max(expirationissuedate) as last_expiration_date,
	max(termnumber) as last_adv_term_value 
from union_temp
group by original_adv_cust_value,pelcro_subid
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
	cast(lead(ordernumber) over (partition by c.customeraccountid,c.subscriptionid order by c.start_date)as varchar) as renewalordernumber,
	lead(start_date) over (partition by c.customeraccountid,c.subscriptionid order by c.start_date)::date as renewalstartdate,
	lead(c.rate) over (partition by c.customeraccountid,c.subscriptionid order by c.start_date)::varchar as renewalrate,
	c.donortype
from cny_i c
left join adv_layer_data r on r.pelcro_subid=c.subscriptionid
where c.expire_date>r.last_expiration_date
	and planid is not null
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
	lead(ordernumber) over (partition by pelcro_subid order by startissuedate) as renewalordernumber,
	lead(startissuedate) over (partition by pelcro_subid order by startissuedate) as renewalstartdate,
	lead(i.amountdue) over (partition by pelcro_subid order by startissuedate)::varchar as renewalrate,
	case when s.iscorporate=TRUE then 'B'
	  when s.isagency=TRUE then 'A'
	  when s.iscomp=TRUE then 'C'
	  when s.isgiftdonor then 'D'
	  when s.isindividual=TRUE then 'I'
	  else 'G' 
	end as donortype
from (select * from prod.pelcro.subscription s where oldproviderid is null) s
join prod.pelcro.invoice i on i.susbcriptionid = s.subscriptionid 
left join prod.pelcro.subscription_plan sp on sp.planid=i.planid
where s.ispaid is true
	and s.issourced is true
	and i.businessunitcode like '%CNY'
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
order by i.pelcro_subid,termnumber,i.startissuedate)









