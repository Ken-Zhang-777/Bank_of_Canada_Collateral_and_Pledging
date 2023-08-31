--first of all, create the table and import the data we need.
DROP TABLE IF EXISTS Col_Trans;
CREATE TABLE Col_Trans (
	`Process_Date`	TEXT,
	`Trade_ID`	TEXT,
	`Transaction_Date`	TEXT,
	`Currency`	TEXT,
	`Customer_ID`	TEXT,
	`Encum_Status`	NUMERIC,
	`Product_Type`	TEXT,
	`PV`	DECIMAL(12,2),
	`PV_CDE`	DECIMAL(12,2),
	`Encum_Mat_Date`	TEXT,
	`Margin_Type`	TEXT,
	`Security_ID`	TEXT,
	`Post_Direction`	TEXT,
	`CSA_ID`	TEXT,
	`Quantity`	NUMERIC
);


DROP TABLE IF EXISTS Customer;
CREATE TABLE Customer (
	`Customer_ID`	TEXT,
	`Customer_Name`	TEXT,
	`Industry`	TEXT,
	`Jurisdiction`	TEXT,
	`CreditRating`	TEXT
);


DROP TABLE IF EXISTS Sec;
CREATE TABLE Sec (
	Security_ID	TEXT,
	Security_ID_2	TEXT,
	Issuer	TEXT,
	Issuer_Credit_Rating	TEXT,
	Industry	TEXT,
	Currency	TEXT,
	Security_Type	TEXT,
	Maturity_date	TEXT,
	Issue_Date	TEXT,
	Coupon	TEXT,
	Price	FLOAT,
	Factor	TEXT,
	MTM_Date	TEXT,
	Fixed_Flag	TEXT,
	primary key (Security_ID)
);


--step 1.create a new table, to add a column of 'counterparty type' for each customer on table customer
create table cus_counterparty as 
select *,
    case
    when industry='Financial' and jurisdiction='Canada' then 'Domestic bank'
    when industry <> 'Financial' and jurisdiction='Canada' then 'Other domestic'
    else 'Foreign Counterparties'
    end as counterparty_type
from customer
;

--step 2.create a new table, to add a column of 'Assert level' for each Security ID on table Sec
create table sec_collateral as 
select *,
    case
    when industry='Sovereign' and Security_Type='Bond' then 'Level 1 Assert'
    when industry not in ('Sovereign', 'Financial', 'Insurance') and Issuer_Credit_Rating like 'A%' and Issuer_Credit_Rating <> 'A-' then 'Level 2 Assert'
    else 'Level 3 Assert'
    end as assert_level
from sec
;

--step 3.create a new table, left join primary table(Col_trans) and table created in step 1, 
--    add a column of 'counter-party type'  for each transaction according to their Customer ID.
create table join_1 as 
select a.*,
    b.counterparty_type
    
from col_trans a left join cus_counterparty b on a.Customer_ID = b.Customer_ID
where a.Product_Type= 'Security'
;

--step.4.create a new table, continue to left join new primary table(step 3) and table created in step 2, 
--    add a column of 'Assert level' for each transaction according to their Security ID.
create table join_2 as 
select a.*,
    b.assert_level   
from join_1 a left join sec_collateral b on a.security_ID = b.security_ID or a.security_ID = b.security_ID_2
;

--step 5. Generate a prototype of the final result table: by result of step 4, classify all transaction and get their sum of Assert of each different level.
create table final_1 as 
select counterparty_type,
        case 
        when Post_direction = 'Deliv to Bank' then 'Collateral Received'
        else 'Collateral Pledged' end as Direction,
        Margin_type,
        sum(case when assert_level='Level 1 Assert' then pv_cde else 0 end) as Level_1_Assert,
        sum(case when assert_level='Level 2 Assert' then pv_cde else 0 end) as Level_2_Assert,
        sum(case when assert_level='Level 3 Assert' then pv_cde else 0 end) as Level_3_Assert
from join_2
group by counterparty_type, Direction, Margin_type
order by counterparty_type, Direction, Margin_type
;

--step 6. check the result of step 5, display the data in a clearer way, also check whether Null is handled in a reasonable way. 
create table final_2 as 
select a.counterparty_type as 'counterparty type',
    b.Direction,
    c.Margin_type as 'collateral type'
from (select distinct counterparty_type from final_1) a
    cross join (select distinct Direction from final_1) b
    cross join (select distinct Margin_type from final_1) c      
;

create table final_result_of_Case_1 as 
select 
    a.'counterparty type',
    a.Direction,
    a.'collateral type',
    round(coalesce(Level_1_Assert, 0),2) as 'Level 1 Assert',
    round(coalesce(Level_2_Assert, 0),2) as 'Level 2 Assert',
    round(coalesce(Level_3_Assert, 0),2) as 'Level 3 Assert'
from final_2 a left join final_1 b on a.'counterparty type'=b.counterparty_type
                                    and a.Direction=b.Direction
                                    and a.'collateral type'=b.Margin_type
                                    ;

