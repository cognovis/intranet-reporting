# /packages/intranet-timesheet2/www/weekly_report.tcl
#
# Copyright (C) 1998-2004 various parties
# The code is based on ArsDigita ACS 3.4
#
# This program is free software. You can redistribute it
# and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation;
# either version 2 of the License, or (at your option)
# any later version. This program is distributed in the
# hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.

# ---------------------------------------------------------------
# Page Contract
# ---------------------------------------------------------------

ad_page_contract {
    Shows a summary of the loged hours by all team members of a project (1 week).
    Only those users are shown that:
    - Have the permission to add hours or
    - Have the permission to add absences AND
	have atleast some absences logged

    @param owner_id	user concerned can be specified
    @param project_id	can be specified
    @param workflow_key workflow_key to indicate if hours have been confirmed      

    @author Malte Sussdorff (malte.sussdorff@cognovis.de)
} {
    { owner_id:integer "" }
    { project_id:integer "" }
    { cost_center_id:integer "" }
    { end_date "" }
    { start_date "" }
    { approved_only_p:integer "0"}
    { workflow_key ""}
    { view_name "hours_list" }
    { view_type "actual" }
    { dimension "hours" }
    { order_by "username,project_name"}
}

# ---------------------------------------------------------------
# Defaults & Security
# ---------------------------------------------------------------

set user_id [ad_maybe_redirect_for_registration]
set admin_p [im_is_user_site_wide_or_intranet_admin $user_id]
set subsite_id [ad_conn subsite_id]
set site_url "/intranet-timesheet2"
set return_url "$site_url/hours_report"
set date_format "YYYY-MM-DD"

# We need to set the overall hours per month an employee is working
# Make this a default for all for now.
set hours_per_month [expr [parameter::get_from_package_key -package_key "intranet-timesheet2" -parameter TimesheetWorkDaysPerYear] * [parameter::get_from_package_key -package_key "intranet-timesheet2" -parameter TimesheetHoursPerDay] / 12] 
set hours_per_absence [parameter::get -package_id [apm_package_id_from_key intranet-timesheet2] -parameter "TimesheetHoursPerAbsence" -default 8.0]

if {"" == $start_date} { 
    set start_date [db_string get_today "select to_char(sysdate,'YYYY-01-01
') from dual"]   
}

if {"" == $end_date} { 
    # if no end_date is given, set it to six months in the future
    set end_date [db_string current_month "select to_char(sysdate + interval '6 month',:date_format) from dual"]
}


# Get the first and last month
set start_month [db_string start_month "select to_char(to_date(:start_date,'YYYY-MM-DD'),'YYMM') from dual"]
set end_month [db_string end_month "select to_char(to_date(:end_date,'YYYY-MM-DD'),'YYMM') from dual"]


if {![im_permission $user_id "view_hours_all"] && $owner_id == ""} {
    set owner_id $user_id
}

# Get the correct view options
# set view_options [db_list_of_lists views {select view_label,view_name from im_views where view_type_id = 1451}]
set view_options {{Hours hours_list}}

# Allow the project_manager to see the hours of this project
if {"" != $project_id} {
    set manager_p [db_string manager "select count(*) from acs_rels ar, im_biz_object_members bom where ar.rel_id = bom.rel_id and object_id_one = :project_id and object_id_two = :user_id and object_role_id = 1301" -default 0]
    if {$manager_p || [im_permission $user_id "view_hours_all"]} {
	set owner_id ""
    }
}

# Allow the manager to see the department
if {"" != $cost_center_id} {
    set manager_id [db_string manager "select manager_id from im_cost_centers where cost_center_id = :cost_center_id" -default ""]
    if {$manager_id == $user_id || [im_permission $user_id "view_hours_all"]} {
        set owner_id ""
    }
}

if { $project_id != "" } {
    set error_msg [lang::message::lookup "" intranet-core.No_name_for_project_id "No Name for project %project_id%"]
    set project_name [db_string get_project_name "select project_name from im_projects where project_id = :project_id" -default $error_msg]
}

# ---------------------------------------------------------------
# Format the Filter and admin Links
# ---------------------------------------------------------------

set form_id "report_filter"
set action_url "/intranet-timesheet2/hours_report"
set form_mode "edit"
if {[im_permission $user_id "view_projects_all"]} {
    set project_options [im_project_options -include_empty 1 -exclude_subprojects_p 0 -include_empty_name [lang::message::lookup "" intranet-core.All "All"]]
} else {
    set project_options [im_project_options -include_empty 0 -exclude_subprojects_p 0 -include_empty_name [lang::message::lookup "" intranet-core.All "All" -member_user_id $user_id]]
}

set company_options [im_company_options -include_empty_p 1 -include_empty_name "[_ intranet-core.All]" -type "CustOrIntl" ]
set levels {{"#intranet-timesheet2.lt_hours_spend_on_projec#" "project"} {"#intranet-timesheet2.lt_hours_spend_on_project_and_sub#" subproject} {"#intranet-timesheet2.hours_spend_overall#" all}}


ad_form \
    -name $form_id \
    -action $action_url \
    -mode $form_mode \
    -method GET \
    -export {start_at duration} \
    -form {
    }

if {[apm_package_installed_p intranet-timesheet2-workflow]} {
    ad_form -extend -name $form_id -form {
	{approved_only_p:text(select),optional {label \#intranet-timesheet2.OnlyApprovedHours\# ?} {options {{[_ intranet-core.Yes] "1"} {[_ intranet-core.No] "0"}}} {value 0}}
    }
}

ad_form -extend -name $form_id -form {
    {project_id:text(select),optional {label \#intranet-cost.Project\#} {options $project_options} {value $project_id}}
}

# Deal with the department
if {[im_permission $user_id "view_hours_all"]} {
    set cost_center_options [im_cost_center_options -include_empty 1 -include_empty_name [lang::message::lookup "" intranet-core.All "All"] -department_only_p 0]
} else {
    # Limit to Cost Centers where he is the manager
    set cost_center_options [im_cost_center_options -include_empty 1 -department_only_p 1 -manager_id $user_id]
}

if {"" != $cost_center_options} {
    ad_form -extend -name $form_id -form {
        {cost_center_id:text(select),optional {label "User's Department"} {options $cost_center_options} {value $cost_center_id}}
    }
}

ad_form -extend -name $form_id -form {
    {dimension:text(select) {label "Dimension"} {options {{Hours hours} {Percentage percentage}}} {value $dimension}}
    {view_type:text(select) {label "Type"} {options {{Planning planning} {Actual actual} {Forecast forecast}}} {value $view_type}}
    {start_date:text(text) {label "[_ intranet-timesheet2.Start_Date]"} {value "$start_date"} {html {size 10}} {after_html {<input type="button" style="height:20px; width:20px; background: url('/resources/acs-templating/calendar.gif');" onclick ="return showCalendar('start_date', 'y-m-d');" >}}}
    {end_date:text(text) {label "[_ intranet-timesheet2.End_Date]"} {value "$end_date"} {html {size 10}} {after_html {<input type="button" style="height:20px; width:20px; background: url('/resources/acs-templating/calendar.gif');" onclick ="return showCalendar('end_date', 'y-m-d');" >}}}
    {view_name:text(select) {label \#intranet-core.View_Name\#} {value "$view_name"} {options $view_options}}
}

eval [template::adp_compile -string {<formtemplate id="$form_id" style="tiny-plain-po"></formtemplate>}]
set filter_html $__adp_output


template::head::add_javascript -src "http://cdn.sencha.com/ext/gpl/4.2.1/ext-all.js" -order 9
template::head::add_javascript -src "hours-report.js" -order 10
set left_navbar_html "
            <div class=\"filter-block\">
                $filter_html
            </div>
"