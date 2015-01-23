# /packages/intranet-reporting/www/timesheet-companies-projects.tcl
#
# Copyright (C) 2003 - 2009 ]project-open[
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.


ad_page_contract {
	testing reports	
    @param start_year Year to start the report
    @param start_unit Month or week to start within the start_year
    @param truncate_note_length Truncate (ellipsis) the note field
	   to the given number of characters. 0 indicates no
	   truncation.
} {
    { start_date "" }
    { end_date "" }
    { level_of_detail 2 }
    { truncate_note_length 4000}
    { output_format "html" }
    { project_id:integer 0}
    { approved_only_p:integer 0}
    { task_id:integer 0}
    { company_id:integer 0}
    { user_id:integer 0}
    { cost_center_id:integer 0}
    { invoice_id:integer 0}
    { invoiced_status "" }
}

# ------------------------------------------------------------
# Security

# Label: Provides the security context for this report
# because it identifies unquely the report's Menu and
# its permissions.
set menu_label "reporting-timesheet-customer-project"
set current_user_id [ad_maybe_redirect_for_registration]

set use_project_name_p [parameter::get_from_package_key -package_key intranet-reporting -parameter "UseProjectNameInsteadOfProjectNr" -default 0]

# Default User = Current User, to reduce performance overhead
if {"" == $start_date && "" == $end_date && 0 == $project_id && 0 == $company_id && 0 == $user_id} { 
    set user_id $current_user_id 
}

set read_p [db_string report_perms "
	select	im_object_permission_p(m.menu_id, :current_user_id, 'read')
	from	im_menus m
	where	m.label = :menu_label
" -default 'f']

# Has the current user the right to edit all timesheet information?
set edit_timesheet_p [im_permission $current_user_id "add_hours_all"]

# ToDo: remove after V3.5: compatibility with old privilege
if {[im_permission $current_user_id "edit_hours_all"]} {set edit_timesheet_p 1 }

set view_hours_all_p [im_permission $current_user_id "view_hours_all"]

if {!$view_hours_all_p} { set user_id $current_user_id }


# If project_id and task_id are set and equal, exclude task_id from sql   
if {0 != $task_id && "" != $task_id && 0 != $project_id && "" != $project_id && $project_id == $task_id} {
    set task_id 0
}

# ------------------------------------------------------------
# Constants

set number_format "999,990.99"


# ------------------------------------------------------------

if {![string equal "t" $read_p]} {
    ad_return_complaint 1 "
    [lang::message::lookup "" intranet-reporting.You_dont_have_permissions "You don't have the necessary permissions to view this page"]"
    return
}

set page_title "Timesheet Report"
set context_bar [im_context_bar $page_title]
set context ""


# ------------------------------------------------------------
# Defaults

set rowclass(0) "roweven"
set rowclass(1) "rowodd"

set days_in_past 7

db_1row todays_date "
select
	to_char(sysdate::date - :days_in_past::integer, 'YYYY') as todays_year,
	to_char(sysdate::date - :days_in_past::integer, 'MM') as todays_month,
	to_char(sysdate::date - :days_in_past::integer, 'DD') as todays_day
from dual
"

if {"" == $start_date} { 
    set start_date "$todays_year-$todays_month-01"
}

# Maxlevel is 4. Normalize in order to show the right drop-down element
if {$level_of_detail > 5} { set level_of_detail 5 }


db_1row end_date "
select
	to_char(to_date(:start_date, 'YYYY-MM-DD') + 31::integer, 'YYYY') as end_year,
	to_char(to_date(:start_date, 'YYYY-MM-DD') + 31::integer, 'MM') as end_month,
	to_char(to_date(:start_date, 'YYYY-MM-DD') + 31::integer, 'DD') as end_day
from dual
"

if {"" == $end_date} { 
    set end_date "$end_year-$end_month-01"
}


set company_url "/intranet/companies/view?company_id="
set project_url "/intranet/projects/view?project_id="
set user_url "/intranet/users/view?user_id="
set hours_url "/intranet-timesheet2/hours/one"
set this_url [export_vars -base "/intranet-reporting/timesheet-customer-project" {start_date end_date level_of_detail project_id task_id company_id user_id} ]

# BaseURL for drill-down. Needs company_id, project_id, user_id, level_of_detail
set base_url [export_vars -base "/intranet-reporting/timesheet-customer-project" {start_date end_date task_id} ]


# ------------------------------------------------------------
# Conditional SQL Where-Clause
#

set criteria [list]

if {0 != $company_id && "" != $company_id} {
    lappend criteria "p.company_id = :company_id"
}

if {0 != $user_id && "" != $user_id} {
    lappend criteria "h.user_id = :user_id"
}

if {0 != $cost_center_id && "" != $cost_center_id} {
    set cc_code [db_string cc_code "select cost_center_code from im_cost_centers where cost_center_id = :cost_center_id" -default "Co"]
    set cc_code_len [string length $cc_code]

    lappend criteria "h.user_id in (
		select	e.employee_id
		from	im_employees e
		where	e.department_id in (
			select	cost_center_id
			from	im_cost_centers
			where	substring(cost_center_code, 1, :cc_code_len) = :cc_code
		)
    )"
}

# MSU: This does not make ANY sense at all. If you have a task, then there will by definition not be any subprojects... strange...
#if {0 != $task_id && "" != $task_id} {
#    lappend criteria "h.project_id = :task_id"
#}

if {0 != $invoice_id && "" != $invoice_id} {
    lappend criteria "h.invoice_id = :invoice_id"
}

if {"" != $invoiced_status} {
    switch $invoiced_status {
	"invoiced" { lappend criteria "h.invoice_id is not null" }
	"not-invoiced" { lappend criteria "h.invoice_id is null" }
	default { ad_return_complaint 1 "<b>Invalid option for 'invoiced_status': '$invoiced_status'</b>:<br>Only 'invoiced' and 'not-invoiced' are allowed." }
    }
}


# Select project & subprojects
set org_project_id $project_id
if {0 != $project_id && "" != $project_id} {
    lappend criteria "p.project_id in (
	select
		p.project_id
	from
		im_projects p,
		im_projects parent_p
	where
		parent_p.project_id = :project_id
		and p.tree_sortkey between parent_p.tree_sortkey and tree_right(parent_p.tree_sortkey)
		and p.project_status_id not in ([im_project_status_deleted])
    )"
}

if {$approved_only_p} {
    set approved_from ", im_timesheet_conf_objects tco"
    lappend criteria "tco.conf_id = h.conf_object_id and tco.conf_status_id = 17010"
} else {
    set approved_from ""
}

set where_clause [join $criteria " and\n	    "]
if { ![empty_string_p $where_clause] } {
    set where_clause " and $where_clause"
}

# ------------------------------------------------------------
# Define the report - SQL, counters, headers and footers 
#

set sql "
select
	h.note,
	h.internal_note,
	to_char(h.day, 'YYYY-MM-DD') as date_pretty,
	to_char(h.day, 'J') as julian_date,
	to_char(h.day, 'J')::integer - to_char(to_date(:start_date, 'YYYY-MM-DD'), 'J')::integer as date_diff,
	coalesce(h.hours,0) as hours,
	to_char(h.billing_rate, :number_format) || '&nbsp;' || co.currency as billing_rate,
	u.user_id,
	im_name_from_user_id(u.user_id) as user_name,
	im_initials_from_user_id(u.user_id) as user_initials,
	main_p.project_id,
	main_p.project_nr,
	main_p.project_name,
	p.project_id as sub_project_id,
	p.project_nr as sub_project_nr,
	p.project_name as sub_project_name,
	c.company_id,
	c.company_path as company_nr,
	c.company_name,
	c.company_id || '-' || main_p.project_id as company_project_id,
	c.company_id || '-' || main_p.project_id || '-' || p.project_id as company_project_sub_id,
	c.company_id || '-' || main_p.project_id || '-' || p.project_id || '-' || u.user_id as company_project_sub_user_id
from
	im_hours h,
	im_projects p,
	im_projects main_p,
	im_companies c,
	users u, 
	im_costs co $approved_from
where
	h.cost_id = co.cost_id 
	and h.project_id = p.project_id
	and main_p.project_status_id not in ([im_project_status_deleted])
	and h.user_id = u.user_id
	and main_p.tree_sortkey = tree_root_key(p.tree_sortkey)
	and h.day >= to_timestamp(:start_date, 'YYYY-MM-DD')
	and h.day < to_timestamp(:end_date, 'YYYY-MM-DD')
	and main_p.company_id = c.company_id
	$where_clause
order by
	c.company_path,
	main_p.project_nr,
	p.project_nr,
	user_name,
	p.project_nr,
	h.day
"

set report_def [list \
	group_by company_id \
	header {
		"\#colspan=99 <a href=$base_url&company_id=$company_id&level_of_detail=4 
		target=_blank><img src=/intranet/images/plus_9.gif border=0></a> 
		<b><a href=$company_url$company_id>$company_name</a></b>"
	} \
	content [list  \
		group_by company_project_id \
		header {
			$company_nr 
			"\#colspan=99 <a href=$base_url&project_id=$project_id&level_of_detail=4 
			target=_blank><img src=/intranet/images/plus_9.gif border=0></a>
			<b><a href=$project_url$project_id>$project_name</a></b>"
		} \
		content [list \
			group_by company_project_sub_id \
			header {
				$company_nr 
				$project_nr 
				"\#colspan=99 <a href=$base_url&project_id=$sub_project_id&level_of_detail=5
				target=_blank><img src=/intranet/images/plus_9.gif border=0></a>
				<b><a href=$project_url$sub_project_id>$sub_project_name</a></b>"
			} \
			content [list \
				group_by company_project_sub_user_id \
				header {
					$company_nr 
					$project_nr 
					$sub_project_nr 
					"\#colspan=99 <a href=$base_url&project_id=$sub_project_id&user_id=$user_id&level_of_detail=5
					target=_blank><img src=/intranet/images/plus_9.gif border=0></a>
					<b><a href=$user_url$user_id>$user_name</a></b>"
				} \
				content [list \
					header {
						$company_nr
						$project_nr
						$sub_project_nr
						$user_initials
						"<nobr>$date_pretty</nobr>"
						$hours_link
						$billing_rate
						"<nobr>$note</nobr>"
					} \
					content {} \
				] \
				footer {
					$company_nr 
					$project_nr 
					$sub_project_nr 
					$user_initials
					""
					"<i>$hours_user_subtotal</i>"
					""
					""
				} \
			] \
			footer {
				$company_nr
				$project_nr
				$sub_project_nr
				""
				""
				"<i>$hours_project_sub_subtotal</i>"
				""
				""
			} \
		] \
		footer {
			$company_nr
			$project_nr
			""
			""
			""
			"<b>$hours_project_subtotal</b>"
			""
			""
		} \
	] \
	footer {"" "" "" "" "" "" "" ""} \
]


# Global header/footer
set header0 {"Customer" "Project" "Subproject" "User" "Date" Hours Rate Note}
set footer0 {"" "" "" "" "" "" "" ""}

# If user is not allowed to see internal rates we remove 'rate' items from record 
if { ![im_permission $current_user_id "fi_view_internal_rates"] } {
    set report_def [string map {\$billing_rate ""} $report_def] 
    set header0 [string map {"Rate" ""} $header0]
}

set hours_user_counter [list \
	pretty_name Hours \
	var hours_user_subtotal \
	reset \$company_project_sub_user_id \
	expr \$hours
]

set hours_project_sub_counter [list \
	pretty_name Hours \
	var hours_project_sub_subtotal \
	reset \$company_project_sub_id \
	expr \$hours
]

set hours_project_counter [list \
	pretty_name Hours \
	var hours_project_subtotal \
	reset \$company_project_id \
	expr \$hours
]

set hours_customer_counter [list \
	pretty_name Hours \
	var hours_customer_subtotal \
	reset \$company_id \
	expr \$hours
]

set counters [list \
	$hours_user_counter \
	$hours_project_sub_counter \
	$hours_project_counter \
	$hours_customer_counter \
]


# ------------------------------------------------------------
# Constants
#

set start_years {2000 2000 2001 2001 2002 2002 2003 2003 2004 2004 2005 2005 2006 2006}
set start_months {01 Jan 02 Feb 03 Mar 04 Apr 05 May 06 Jun 07 Jul 08 Aug 09 Sep 10 Oct 11 Nov 12 Dec}
set start_weeks {01 1 02 2 03 3 04 4 05 5 06 6 07 7 08 8 09 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 29 29 30 30 31 31 32 32 33 33 34 34 35 35 36 36 37 37 38 38 39 39 40 40 41 41 42 42 43 43 44 44 45 45 46 46 47 47 48 48 49 49 50 50 51 51 52 52}
set start_days {01 1 02 2 03 3 04 4 05 5 06 6 07 7 08 8 09 9 10 10 11 11 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20 21 21 22 22 23 23 24 24 25 25 26 26 27 27 28 28 29 29 30 30 31 31}
# ------------------------------------------------------------
# Start formatting the page
#


# ------------------------------------------------------------
# Start Formatting the HTML Page Contents

set project_id $org_project_id

set form_id "timesheet_filter"
set action_url "/intranet-reporting/timesheet-customer-project"
set form_mode "edit"
set company_options [im_company_options -include_empty_p 1 -include_empty_name "[_ intranet-core.All]" -type "CustOrIntl" ]
set project_options [im_project_options -include_empty 1 -exclude_subprojects_p 0 -include_empty_name [lang::message::lookup "" intranet-core.All "All"]]
set cost_center_options [im_cost_center_options -include_empty 1 -include_empty_name [lang::message::lookup "" intranet-core.All "All"] -department_only_p 1]
set user_options [im_profile::user_options -profile_ids [list [im_employee_group_id] [im_freelance_group_id]]]
set user_options [linsert $user_options 0 [list [lang::message::lookup "" intranet-core.All "All"] ""]]
set levels {{"Customer Only" 1} {"Customer+Project" 2} {"Customer+Project+Sub" 3} {"Customer+Project+Sub+User" 4} {"All Details" 5}} 
set truncate_note_options {{"Full Length" 4000} {"Standard (80)" 80} {"Short (20)" 20}} 
set invoiced_status_options {{"All" ""} {"Only invoiced hours" "invoiced"} {"Only not invoiced hours" "not-invoiced"}}


ad_form \
    -name $form_id \
    -action $action_url \
    -mode $form_mode \
    -method GET \
    -export {invoice_id} \
    -form {
	{level_of_detail:text(select) {label "Level of Details"} {options $levels} {value $level_of_detail}}
	{start_date:text(text) {label "[_ intranet-timesheet2.Start_Date]"} {value "$start_date"} {html {size 10}} {after_html {<input type="button" style="height:20px; width:20px; background: url('/resources/acs-templating/calendar.gif');" onclick ="return showCalendar('start_date', 'y-m-d');" >}}}
	{end_date:text(text) {label "[_ intranet-timesheet2.End_Date]"} {value "$end_date"} {html {size 10}} {after_html {<input type="button" style="height:20px; width:20px; background: url('/resources/acs-templating/calendar.gif');" onclick ="return showCalendar('end_date', 'y-m-d');" >}}}
	{company_id:text(select),optional {label \#intranet-core.Customer\#} {options $company_options} {value $company_id}}
        {project_id:text(select),optional {label \#intranet-cost.Project\#} {options $project_options} {value $project_id}}
    }

if {[apm_package_installed_p intranet-timesheet2-workflow]} {
    ad_form -extend -name $form_id -form {
	{approved_only_p:text(select),optional {label \#intranet-timesheet2-workflow.Approved\# ?} {options {{[_ intranet-core.Yes] "1"} {[_ intranet-core.No] "0"}}} {value 0}}
    }
}

if {$view_hours_all_p} {
    ad_form -extend -name $form_id -form {
        {cost_center_id:text(select),optional {label "User's Department"} {options $cost_center_options} {value $cost_center_id}}
        {user_id:text(select),optional {label "User"} {options $user_options} {value $user_id}}
	{invoiced_status:text(select) {label "Invoiced Status"} {options $invoiced_status_options} {value $invoiced_status}}
    }
}

if {$level_of_detail > 3} {
    ad_form -extend -name $form_id -form {
	{truncate_note_length:text(select) {label "Size of Note Field"} {options $truncate_note_options} {value $truncate_note_length}}
    }
}

if {[info exists task_id]} {
    ad_form -extend -name $form_id -form {
	{task_id:text(hidden),optional}
    }
}

# List to store the output_format_options
set output_format_options [list [list HTML "html"] [list CSV "csv"]]

# Run callback to extend the filter and/or add items to the output_format_options
callback im_timesheet_report_filter -form_id $form_id
ad_form -extend -name $form_id -form {
    {output_format:text(select),optional {label "#intranet-openoffice.View_type#"} {options $output_format_options}}
}

eval [template::adp_compile -string {<formtemplate id="$form_id" style="tiny-plain-po"></formtemplate>}]
set filter_html $__adp_output

# Create a ns_set with all local variables in order
# to pass it to the SQL query
set form_vars [ns_set create]
foreach varname [info locals] {

    # Don't consider variables that start with a "_", that
    # contain a ":" or that are array variables:
    if {"_" == [string range $varname 0 0]} { continue }
    if {[regexp {:} $varname]} { continue }
    if {[array exists $varname]} { continue }

    # Get the value of the variable and add to the form_vars set
    set value [expr "\$$varname"]
    ns_set put $form_vars $varname $value
}

callback im_timesheet_report_before_render -view_name "timesheet_csv" \
    -view_type $output_format -sql $sql -table_header $page_title -variable_set $form_vars

# Write out HTTP header, considering CSV/MS-Excel formatting
im_report_write_http_headers -output_format $output_format -report_name "timesheet-customer-project"


switch $output_format {
    html {
	ns_write "
	[im_header $page_title]
	[im_navbar reporting]
	<div id=\"slave\">
	<div id=\"slave_content\">

	<div class=\"filter-list\">

	<div class=\"filter\">
	<div class=\"filter-block\">

        $filter_html

	</div>
	</div>
	<div id=\"fullwidth-list\" class=\"fullwidth-list\">
	[im_box_header $page_title]

	<table border=0 cellspacing='2' cellpadding='2' class='table_list_simple'>\n"
    }

    printer {
	ns_write "
	<link rel=StyleSheet type='text/css' href='/intranet-reporting/printer-friendly.css' media=all>
        <div class=\"fullwidth-list\">
	<table border='0' cellspacing='1' cellpadding='1' rules='all'>
	<colgroup>
		<col id=datecol>
		<col id=hourcol>
		<col id=datecol>
		<col id=datecol>
		<col id=hourcol>
		<col id=hourcol>
		<col id=hourcol>
	</colgroup>
	"
    }
}


im_report_render_row \
    -output_format $output_format \
    -row $header0 \
    -row_class "rowtitle" \
    -cell_class "rowtitle"


set footer_array_list [list]
set last_value_list [list]
set class "rowodd"

db_foreach sql $sql {

	# Does the user prefer to read project_name instead of project_nr? (Genedata...)
	if {$use_project_name_p} { 
	    set project_nr $project_name
	    set sub_project_name [im_reporting_sub_project_name_path $sub_project_id]
	    set sub_project_nr $sub_project_name
	    set user_initials $user_name
	    set company_nr $company_name
	}

	if {"" != $internal_note} {
	    set note "$note / $internal_note"
	}
	if {[string length $note] > $truncate_note_length} {
	    set note "[string range $note 0 $truncate_note_length] ..."
	}
	set hours_link $hours
	if {$edit_timesheet_p} {
	    set hours_link " <a href=\"[export_vars -base $hours_url {julian_date user_id {project_id $sub_project_id} {return_url $this_url}}]\">$hours</a>\n"
	}

	im_report_display_footer \
	    -output_format $output_format \
	    -group_def $report_def \
	    -footer_array_list $footer_array_list \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class

	im_report_update_counters -counters $counters
	set hours_user_subtotal [expr round(100.0 * $hours_user_subtotal) / 100.0]
	set hours_project_sub_subtotal [expr round(100.0 * $hours_project_sub_subtotal) / 100.0]
	set hours_project_subtotal [expr round(100.0 * $hours_project_subtotal) / 100.0]

	set last_value_list [im_report_render_header \
	    -output_format $output_format \
	    -group_def $report_def \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class
	]

	set footer_array_list [im_report_render_footer \
	    -output_format $output_format \
	    -group_def $report_def \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class
	]
}

im_report_display_footer \
    -output_format $output_format \
    -group_def $report_def \
    -footer_array_list $footer_array_list \
    -last_value_array_list $last_value_list \
    -level_of_detail $level_of_detail \
    -display_all_footers_p 1 \
    -row_class $class \
    -cell_class $class

im_report_render_row \
    -output_format $output_format \
    -row $footer0 \
    -row_class $class \
    -cell_class $class


# Write out the HTMl to close the main report table
# and write out the page footer.
#
switch $output_format {
    html { ns_write "</table>[im_box_footer]</div></div></div>\n</div></div>[im_footer]\n"}
    printer { ns_write "</table>\n</div>\n"}
    cvs { }
}
