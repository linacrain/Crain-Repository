with 








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
ccb_I as (
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
	i.paidatdatetime as orderdate
FROM prod.pelcro.subscription s
left join rolled_up_invoice i on i.susbcriptionid = s.subscriptionid
where s.businessunitcode = 'CCB'
	and s.ispaid is true
order by currentperiodenddatetime
)

select adv_sub_id,
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
orderdate,
case when ps.planinterval like '%year%' then 'Annual'
		 when ps.planinterval like '%month%' then 'Monthly'
		 when ps.planinterval is null and isannualterm=true then 'Annual'
		 when ps.planinterval is null and ismonthlyterm=true then 'Monthly'
	else 'day' end as termlength,
case when ps.isautorenew is null then 'N'
		else 'Y'
	end as isautorenew
from ccb_i c
left join prod.pelcro.subscription_plan ps on ps.planid=c.planid