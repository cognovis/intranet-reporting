-- upgrade-3.2.6.0.0-3.2.7.0.0.sql

create or replace function inline_1 ()
returns integer as '
declare
      -- Menu IDs
      v_menu                  integer;
      v_admin_menu            integer;
      -- Groups
      v_admins                integer;
      v_senman                integer;
      v_accounting                integer;
begin
    select group_id into v_admins from groups where group_name = ''P/O Admins'';
    select group_id into v_accounting from groups where group_name = ''Accounting'';
    select group_id into v_senman from groups where group_name = ''Senior Managers'';

    select menu_id
    into v_admin_menu
    from im_menus
    where label=''reporting-finance'';

    v_menu := im_menu__new (
        null,                   -- p_menu_id
        ''acs_object'',           -- object_type
        now(),                  -- creation_date
        null,                   -- creation_user
        null,                   -- creation_ip
        null,                   -- context_id
        ''intranet-reporting'',      -- package_name
        ''reporting-finance-cube'',   -- label
        ''Finance Cube'',            -- name
        ''/intranet-reporting/finance-cube'', -- url
        110,                     -- sort_order
        v_admin_menu,         -- parent_menu_id
        null                    -- p_visible_tcl
    );

    PERFORM acs_permission__grant_permission(v_menu, v_admins, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_accounting, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_senman, ''read'');
    return 0;
end;' language 'plpgsql';
select inline_1 ();
drop function inline_1();




create or replace function inline_1 ()
returns integer as '
declare
      -- Menu IDs
      v_menu                  integer;
      v_admin_menu            integer;
      -- Groups
      v_admins                integer;
      v_senman                integer;
      v_proman                integer;
      v_accounting                integer;
begin
    select group_id into v_admins from groups where group_name = ''P/O Admins'';
    select group_id into v_accounting from groups where group_name = ''Accounting'';
    select group_id into v_senman from groups where group_name = ''Senior Managers'';
    select group_id into v_proman from groups where group_name = ''Project Managers'';

    select menu_id
    into v_admin_menu
    from im_menus
    where label=''reporting-timesheet'';

    v_menu := im_menu__new (
        null,                   -- p_menu_id
        ''acs_object'',           -- object_type
        now(),                  -- creation_date
        null,                   -- creation_user
        null,                   -- creation_ip
        null,                   -- context_id
        ''intranet-reporting'',      -- package_name
        ''reporting-timesheet-cube'',   -- label
        ''Timesheet Cube'',            -- name
        ''/intranet-reporting/timesheet-cube'', -- url
        110,                     -- sort_order
        v_admin_menu,         -- parent_menu_id
        null                    -- p_visible_tcl
    );

    PERFORM acs_permission__grant_permission(v_menu, v_admins, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_accounting, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_senman, ''read'');
    PERFORM acs_permission__grant_permission(v_menu, v_proman, ''read'');
    return 0;
end;' language 'plpgsql';
select inline_1 ();
drop function inline_1();





-- ------------------------------------------------
-- Add a ? to the end of the reports to pass-on parameters
update im_menus set url = url || '?'
where label = 'reporting-timesheet-customer-project';

update im_menus set url = url || '?'
where label = 'reporting-timesheet-cube';
