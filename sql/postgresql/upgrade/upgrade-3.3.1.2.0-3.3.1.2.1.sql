-- upgrade-3.3.1.2.0-3.3.1.2.1.sql

SELECT acs_log__debug('/packages/intranet-reporting/sql/postgresql/upgrade/upgrade-3.3.1.2.0-3.3.1.2.1.sql','');


create or replace function inline_0 ()
returns integer as '
declare
	v_count			integer;
begin
	select  count(*) into v_count from user_tab_columns
	where   lower(table_name) = ''im_reports'' and lower(column_name) = ''report_code'';
	IF v_count > 0 THEN return 0; END IF;
	
	alter table im_reports add report_code varchar(100);
	
    return 0;
end;' language 'plpgsql';
select inline_0 ();
drop function inline_0();


