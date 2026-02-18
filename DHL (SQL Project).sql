-- ---------------------------------Logistics Optimization for Delivery Routes – DHL ---------------------------------------------------------------

-- first converting all xlsx files into csv format with the help of excel workbooks (Save as type: CSV (Comma delimited) (*.csv))


create database DHL;
use DHL;

-- now importing all tables one by one in DHL database

select * from dhl_delivery_agents;
select * from dhl_orders;
select * from dhl_routes;
select * from dhl_shipments;
select * from dhl_warehouses;

-- ---------------------------------Note: Data Quality Issues---------------------------------------------------------------

-- While working on DHL SQL project, I have identified a data quality issue in the dataset.
-- Issue in Shipment Table (Delay Hours vs Delay Reason)
-- As per the business logic: 
-- - Delay Hours = 0 then Delay Reason should be 'No Delay'
-- - Delay Hours greater than 0 then Delay reason should be one of the following: 
-- 'Weather'
-- 'Technical Issue'
-- 'Traffic'

-- However, in the shipment table, many records do not follow this rule. 
-- Examples observed: 
-- Some records (actually 15 records) have Delay Hours = 0 but the Delay Reason shows 'Weather' / 'Technical Issue' / 'Traffic'. 
-- This creates a mismatch between Delay Hours and Delay reason, which affects the accuracy of Delay analysis. 

-- So, to fix this issue I have updated the column (Delay Reason) in which if Delay Hours is 0 then it shows 'No Delay'.

update dhl_shipments
set Delay_Reason = 'No Delay'
where Delay_Hours = 0;

-- --------------------------------------------------------Note----------------------------------------------------------------------

-- additional sql queries were written beyond the given tasks to perform deeper analysis and derive further business insights.



-- ---------------------------------Task 1: Data Cleaning & Preparation---------------------------------------------------------------

-- Task 1.1: Identify and delete duplicate Order_ID or Shipment_ID records.

select order_id, count(*) as count
from dhl_orders
group by order_id
having count>1;

select shipment_id, count(*) as count 
from dhl_shipments
group by shipment_id
having count>1;

-- no duplicate records were found in both the table.


-- Task 1.2: Replace null or missing Delay_Hours values in the Shipments Table with the average delay for that Route_ID. 

select *
from dhl_shipments
where Delay_Hours is null;

-- no null or missing delay hours values were found in the shipments table.
-- if null or missing vlaues were found then we could use:

update dhl_shipments s
join (
    select Route_ID, avg(Delay_Hours) as avg_delay
    from dhl_shipments
    group by Route_ID
) r
on s.Route_ID = r.Route_ID
set s.Delay_Hours = r.avg_delay
where s.Delay_Hours is null;


-- Task 1.3: Convert all date columns (Order_Date, Pickup_Date, Delivery_Date) into YYYY-MM-DD HH:MM:SS format using SQL date functions.

-- order table
update dhl_orders
set order_date = str_to_date(Order_Date, '%Y-%m-%d %H:%i:%s');

select 
date_format(Order_Date, '%Y-%m-%d %H:%i:%s') as Order_Date
from dhl_orders;

alter table dhl_orders
modify Order_Date datetime;

-- shipment table
update dhl_shipments
set Pickup_Date   = str_to_date(Pickup_Date, '%Y-%m-%d %H:%i:%s'),
    Delivery_Date = str_to_date(Delivery_Date, '%Y-%m-%d %H:%i:%s');

select 
date_format(Pickup_Date, '%Y-%m-%d %H:%i:%s') as Pickup_Date,
date_format(Delivery_Date, '%Y-%m-%d %H:%i:%s') as Delivery_Date
from dhl_shipments;

alter table dhl_shipments
modify Pickup_Date datetime,
modify Delivery_Date datetime;


-- Task 1.4: Ensure that no Delivery_Date occurs before Pickup_Date (flag such records). 

select *
from dhl_shipments
where delivery_Date < pickup_date;

-- No Delivery_Date occured before Pickup_Date

select *,
case
    when delivery_date < pickup_date then 'invalid'
    else 'valid'
end as date_validation_flag
from dhl_shipments;


-- Task 1.5: Validate referential integrity between Orders, Routes, Warehouses, and Shipments.
 
-- shipments --> orders
select s.*
from dhl_shipments s
left join dhl_orders o
on s.order_id = o.order_id
where o.order_id is null;

-- shipments --> routes
select s.*
from dhl_shipments s
left join dhl_routes r
on s.route_id = r.route_id
where r.route_id is null;

-- shipments --> warehouses
select s.*
from dhl_shipments s
left join dhl_warehouses w
on s.warehouse_id = w.warehouse_id
where w.warehouse_id is null;

-- orders --> routes
select o.*
from dhl_orders o
left join dhl_routes r
on o.route_id = r.route_id
where r.route_id is null;

-- orders --> warehouses
select o.* 
from dhl_orders o 
left join dhl_warehouses w
on o.warehouse_id = w.warehouse_id 
where w.warehouse_id is null;



-- ---------------------------------Task 2: Delivery Delay Analysis---------------------------------------------------------------

-- Task 2.1 Calculate delivery delay (in hours) for each shipment using Delivery_Date – Pickup_Date. 

-- Here question framing is not correct the question should be:
-- Calculate Transit_Time (in hours) for each shipment using Delivery_Date – Pickup_Date. 
-- Because Delivery Delay (in hours) is already given in the shipment table.
-- so,calculating transit time in hours for each shipment makes more sense.

select Shipment_ID, 
round(timestampdiff(minute, Pickup_Date, Delivery_Date)/ 60, 1) as Transit_Time_Hours 
from dhl_shipments
order by Transit_TIme_Hours;

-- i have taken minutes then convert it into hours so that we can get precise value of transit time (in decimals)
-- now, calculating avg transit time of the each shipment for further analysis.

select round(avg(timestampdiff(minute, Pickup_Date, Delivery_Date)/ 60), 2)
as Avg_Transit_Time_Hours 
from dhl_shipments;


-- Task 2.2: Find the Top 10 delayed routes based on average delay hours.

select Route_ID, 
round(avg(Delay_Hours),1) as Avg_Delay_Hours
from dhl_shipments
group by Route_ID
order by Avg_Delay_Hours Desc
limit 10;

select round(avg(Delay_Hours),3) as Avg_Delay
from dhl_shipments;


-- Task 2.3: Use SQL window functions to rank shipments by delay within each Warehouse_ID. 

select Warehouse_ID, Shipment_ID, Delay_Hours,
dense_rank() over(partition by Warehouse_ID order by Delay_Hours desc) as `Rank`
from dhl_shipments;


-- Task 2.4: Identify the average delay per Delivery_Type (Express / Standard) to compare service-level efficiency. 

select Delivery_Type, 
round(avg(Delay_Hours),1) as Avg_Delay_Hours
from dhl_shipments as s
join dhl_orders as o
on s.Order_ID = o.Order_ID
group by Delivery_Type;



-- ---------------------------------Task 3: Route Optimization Insights---------------------------------------------------------------

-- For each route, calculate:

-- Task 3.1: Average transit time (in hours) across all shipments. 

With CTE as(
select Route_ID,
timestampdiff(minute, Pickup_Date, Delivery_Date) / 60 as Transit_Time_Hours
from dhl_shipments)

select Route_ID, 
round(Avg(Transit_Time_Hours),1) as Avg_Transit_Time
from CTE
group by Route_ID
order by Route_ID;


-- Task 3.2: Average delay (in hours) per route.

select Route_ID, 
round(avg(Delay_Hours),1) as Avg_Delay_Hours
from dhl_shipments
group by Route_ID
order by Route_ID;


-- Task 3.3: Distance-to-time efficiency ratio = Distance_KM / Avg_Transit_Time_Hours. 

select Route_ID,
round(Distance_KM / Avg_Transit_Time_Hours, 1) as Efficiency_Ratio
from dhl_routes;


-- Task 3.4: Identify 3 routes with the worst efficiency ratio (lowest distance-to-time). 

select Route_ID,
round(Distance_KM / Avg_Transit_Time_Hours, 1) as Efficiency_Ratio
from dhl_routes
order by Efficiency_Ratio
limit 3;


-- Task 3.5: Find routes with >20% of shipments delayed beyond expected transit time. 

with flag as (
select Route_ID, Shipment_ID,
case 
	when Delay_Hours = 0 then 0
    else 1 
end as Delay_Flag
from dhl_shipments),

percentage as (
select Route_ID, sum(Delay_Flag) as Delayed_Shipments, count(Shipment_ID) as Total_Shipments,
sum(Delay_Flag)/count(Shipment_ID)*100 as Delayed_Percentage
from Flag
group by Route_ID
order by Route_ID)

select Route_ID, Delayed_Percentage
from percentage
where Delayed_Percentage > 20;


-- Task 3.6: Recommend potential routes or hub pairs for optimization. 

-- Analysis shows that the overall average transit time is ~53.4 hours,
-- while several routes exceed 70–80 hours, indicating severe inefficiencies.
--
-- the distance-to-time efficiency ratio varies widely from ~38 km/hr to
-- over 545 km/hr, with routes such as R003, R015, and R006 showing the
-- lowest efficiency and requiring immediate optimization.
--
-- Additionally, delay percentage analysis indicates that many routes
-- have more than 80% of shipments delayed beyond expected transit time,
-- highlighting frequent sla breaches.
--
-- It is recommended to prioritize these low-efficiency and high-delay
-- routes and their associated hub pairs for route redesign, SLA
-- recalibration, and capacity optimization to improve network performance.



-- ---------------------------------Task 4: Warehouse Performance---------------------------------------------------------------

-- Task 4.1: Find the top 3 warehouses with the highest average delay in shipments dispatched. 

select Warehouse_ID, round(avg(Delay_Hours),1) as Avg_Delay_Hours
from dhl_shipments
group by Warehouse_ID
order by Avg_Delay_Hours desc
limit 3;


-- Task 4.2: Calculate total shipments vs delayed shipments for each warehouse. 

with cte as (
select Warehouse_ID, Shipment_ID,
case
	when Delay_Hours = 0 then 0
    else 1 
end as Delay_Flag
from dhl_shipments
)
select
Warehouse_ID,
count(Shipment_ID) as Total_Shipments,
sum(Delay_Flag) as Delayed_Shipments
from cte
group by Warehouse_ID
order by Warehouse_ID;


-- Task 4.3: Use CTEs to identify warehouses where average delay exceeds the global average delay. 

with CTE as (
select Warehouse_ID,
avg(Delay_Hours) over(partition by Warehouse_ID) as Avg_Delay,
avg(Delay_Hours) over() as Global_Avg_Delay
from dhl_shipments)

select distinct(Warehouse_ID), Avg_Delay, Global_Avg_Delay
from CTE
where Avg_Delay > Global_Avg_Delay ;


-- Task 4.4: Rank all warehouses based on on-time delivery percentage. 

with flag as (
select Warehouse_ID, 
case
	when Delay_Hours = 0 then 1
    else 0
end as On_Time_Flag    
from dhl_shipments),

percentage as (
select Warehouse_ID, sum(On_Time_Flag) as On_Time_Delivery, count(*) as Total_Delivery,
sum(On_Time_Flag)/count(*) * 100  as On_Time_Delivery_Percentage
from flag
group by Warehouse_ID)

select Warehouse_ID, On_Time_Delivery_Percentage, 
rank() over(order by On_Time_Delivery_Percentage desc) as `Rank`
from percentage;



-- ---------------------------------Task 5: Delivery Agent Performance---------------------------------------------------------------

-- Task 5.1: Rank delivery agents (per route) by on-time delivery percentage. 

with flag as (
select Route_ID, Agent_ID,
case
	when Delay_Hours = 0 then 1
    else 0
end On_Time_Flag
from dhl_shipments),

percentage as (
select Route_ID, Agent_ID, sum(On_Time_Flag) as On_Time_Delivery, count(*) as Total_Delivery,
sum(On_Time_Flag)/count(*) *100 as On_Time_Delivery_Percentage
from flag
group by Route_ID, Agent_ID)

select Route_ID, Agent_ID, On_Time_Delivery, Total_Delivery, On_Time_Delivery_Percentage,
dense_rank() over(partition by Route_ID order by On_Time_Delivery_Percentage desc) as `Rank`
from percentage;


-- Task 5.2: Find agents whose on-time % is below 85%.

with flag as (
select Agent_ID,
case
	when Delay_Hours = 0 then 1
    else 0
end On_Time_Flag
from dhl_shipments),

percentage as (
select Agent_ID, sum(On_Time_Flag) as On_Time_Delivery, count(*) as Total_Delivery,
(sum(On_Time_Flag)*100/count(*)) as On_Time_Delivery_Percentage
from flag
group by Agent_ID)

select Agent_ID, On_Time_Delivery, Total_Delivery, On_Time_Delivery_Percentage
from percentage
where On_Time_Delivery_Percentage < 85
order by Agent_ID;
    
    
-- Task 5.3: Compare the average rating and experience (in years) of the top 5 vs bottom 5 agents using subqueries. 

(select 'Top 5 Agents' as Agent_Group,
avg(d.Avg_Rating) as Avg_Rating,
avg(d.Experience_Years) as Avg_Experience_Years
from dhl_delivery_agents d
join (
    select Agent_ID
    from dhl_shipments
    group by Agent_ID
    order by (sum(case when Delay_Hours = 0 
    then 1 else 0 end) * 100.0 / count(*)) desc
    limit 5
) t
on d.Agent_ID = t.Agent_ID)
union all (
select
'Bottom 5 Agents' as Agent_Group,
avg(d.Avg_Rating) as Avg_Rating,
avg(d.Experience_Years) as Avg_Experience_Years
from dhl_delivery_agents d
join (
    select Agent_ID
    from dhl_shipments
    group by Agent_ID
    order by (sum(case when Delay_Hours = 0 
    then 1 else 0 end) * 100.0 / count(*)) asc
    limit 5
) b
on d.Agent_ID = b.Agent_ID);



-- Task 5.4: Suggest training or workload balancing strategies for low-performing agents based on insights. 

-- Analysis shows that the majority of delivery agents have on-time delivery
-- percentages below 85%, with on-time performance ranging from ~0% to ~24%.
--
-- Several agents exhibit single-digit or zero on-time delivery percentages,
-- indicating significant performance gaps.
--
-- It is recommended to provide targeted training for agents with on-time
-- performance below 10%, focusing on route knowledge, time management,
-- and handling delivery exceptions.
--
-- Workload balancing should be applied by assigning high-risk or complex
-- routes to higher-performing agents (on-time performance above ~20%)
-- while gradually improving low-performing agent exposure.
--
-- These actions are expected to improve overall delivery reliability
-- and reduce agent-level contribution to delays.




-- ---------------------------------Task 6: Shipment Tracking Analytics---------------------------------------------------------------

-- Task 6.1: For each shipment, display the latest status (Delivered, In Transit, or Returned) along with the latest Delivery_Date.  

select Shipment_ID, Delivery_Status, Delivery_Date
from dhl_shipments;


select s.Shipment_ID,
       s.Delivery_Status,
       s.Delivery_Date
from dhl_shipments s
join (
    select Shipment_ID,
	max(Delivery_Date)
    as Latest_Delivery_Date
    from dhl_shipments
    group by Shipment_ID
) latest
on s.Shipment_ID = 
latest.Shipment_ID
and s.Delivery_Date = 
latest.Latest_Delivery_Date;

-- Both query gave same result.

-- Now, Calculating how many Shipments have delivered, in transit, or cancelled for further analysis.

select Delivery_Status, count(Shipment_ID) as Total_Shipments
from dhl_shipments
group by Delivery_Status;


-- Task 6.2: Identify routes where the majority of shipments are still “In Transit” or “Returned”.

with route_status as (
    select
    Route_ID,
    case
        when Delivery_Status in 
        ('In Transit', 'Returned') then 1
        else 0
    end as Issue_Flag
    from dhl_shipments
)
select
Route_ID,
count(*) as Total_Shipments,
sum(Issue_Flag) as Issue_Shipments
from route_status
group by Route_ID
having sum(Issue_Flag) > count(*) / 2;



-- Task 6.3:  Find the most frequent delay reasons (if available in delay-related columns or flags). 

select Delay_Reason, count(*) as Frequency
from dhl_shipments
where Delay_Reason not in ('No Delay')
group by Delay_Reason
order by Frequency desc;


-- Task 6.4: Identify orders with exceptionally high delay (>120 hours) to investigate potential bottlenecks. 

select Order_ID, Delay_Hours
from dhl_shipments
where Delay_Hours > 120
order by Delay_Hours desc;

with cte as (
select Order_ID, Delay_Hours
from dhl_shipments
where Delay_Hours > 120)

select Order_ID, Avg(Delay_Hours) as Avg_Delay
from cte 
group by Order_ID
order by Avg_Delay desc;


-- the first query lists all shipment-level records with extreme delays
-- to directly identify affected orders.
--
-- the second query aggregates these records at the order level
-- to calculate the average delay per order, enabling deeper
-- bottleneck investigation where orders have multiple shipments.


-- ---------------------------------Task 7: Advanced KPI Reporting---------------------------------------------------------------

-- Create SQL queries to calculate and summarize the following KPIs: 

-- Task 7.1: Average Delivery Delay per Source_Country.

select r.Source_Country,
round(avg(s.Delay_Hours), 1) as Avg_Delivery_Delay_Hours
from dhl_shipments s
join dhl_routes r
on s.Route_ID = r.Route_ID
group by r.Source_Country
order by Avg_Delivery_Delay_Hours desc;


-- Task 7.2: On-Time Delivery % = (Total On-Time Deliveries / Total Deliveries) * 100.

with cte as (
select
case
	when Delay_Hours = 0 then 1
    else 0
end as On_Time_Deliveries    
from dhl_shipments)

select round(sum(On_Time_Deliveries)/count(*) *100 ,1) as On_Time_Delivery_Percentage
from cte;


-- Task 7.3: Average Delay (in hours) per Route_ID.      

select
Route_ID,
round(avg(Delay_Hours), 1) as Avg_Delay_Hours
from dhl_shipments
group by Route_ID
order by Avg_Delay_Hours desc;


-- Task 7.4: Warehouse Utilization % = (Shipments_Handled / Capacity_per_day) * 100.

with warehouse_shipments as (
    select
    w.Warehouse_ID,
    w.Capacity_per_day,
    count(s.Shipment_ID) as Shipments_Handled
    from dhl_warehouses w
    left join dhl_shipments s
    on w.Warehouse_ID = s.Warehouse_ID
    group by w.Warehouse_ID, w.Capacity_per_day
)
select
Warehouse_ID,
Shipments_Handled,
Capacity_per_day,
round(Shipments_Handled * 100.0 / Capacity_per_day,1) 
as Warehouse_Utilization_Percentage
from warehouse_shipments
order by Warehouse_Utilization_Percentage desc;


-- x-----------------------x---------------------x-----------------------x------------------------x------------------------x--------








































