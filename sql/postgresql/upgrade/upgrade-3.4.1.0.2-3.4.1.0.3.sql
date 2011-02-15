-- upgrade-3.4.1.0.2-3.4.1.0.3.sql

-- SELECT acs_log__debug('/packages/intranet-reporting/sql/postgresql/upgrade/upgrade-3.4.1.0.2-3.4.1.0.3.sql','');

create or replace function im_expense_bundle__get_acc_amount(integer, varchar)
returns varchar as '
DECLARE
        p_bundle_id             alias for $1;
        p_currency              alias for $2;
        v_amount_sum            decimal;
BEGIN

        select
                sum(coalesce(co.amount,0)) as amount_sum
	into 
		v_amount_sum
        from
                im_costs co LEFT OUTER JOIN (select * from im_expenses) exp on (co.cost_id = exp.expense_id)
        where
                co.currency = p_currency
                and exp.bundle_id = p_bundle_id;
        return v_amount_sum;

end;' language 'plpgsql';



