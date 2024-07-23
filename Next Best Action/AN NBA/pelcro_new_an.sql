with new_cust_t as (
select distinct
	s.customeraccountid::varchar as shiptocustomernumber,
	null::numeric as original_adv_cust_value,
	i.invoiceid,
	s.subscriptionid,
	i.paidatdatetime as orderdate,
	i.businessunitcode as brand, 
	i.planproductname as pubcode,
	null::numeric as adv_subid,
	i.susbcriptionid::numeric as pelcro_subid,
	dense_rank() over (partition by i.susbcriptionid order by startissuedate) as termnumber,
	case when i.subscriptioncurrentperiodstartdatetime is null then subscriptionstartdatetime
	  else subscriptioncurrentperiodstartdatetime 
	end as startissuedate,
	i.subscriptioncurrentperiodenddatetime as expirationissuedate,
	i.amountdue AS rate,
	i.amountpaid,
	i.amountdue,
	case when s.isannualterm=TRUE then 'Annual'
	when s.ismonthlyterm=TRUE then 'Monthly'
	else 'Other' end as termlength,
	case when s.iscorporate=TRUE then 'B'
	  when s.isagency=TRUE then 'A'
	  when s.iscomp=TRUE then 'C'
	  when s.isgiftdonor then 'D'
	  when s.isindividual=TRUE then 'I'
	  else 'G' 
	end as donortype,
	i.billingtype,
	case when i.planid is null then s.planid
	else i.planid 
	end as planid
from (select * from prod.pelcro.subscription s where oldproviderid is null) s
left join prod.pelcro.invoice i on i.susbcriptionid = s.subscriptionid 
where s.ispaid is true
	and s.issourced is true
	and i.businessunitcode='ANG'
	and s.isindividual=TRUE
order by pelcro_subid,termnumber)

select * from new_cust_t where startissuedate<=date('2024-05-31')
