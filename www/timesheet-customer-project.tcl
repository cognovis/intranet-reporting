# /packages/intranet-reporting/www/timesheet-companies-projects.tcl
#
# Copyright (C) 2003-2004 Project/Open
#
# All rights reserved. Please check
# http://www.project-open.com/ for licensing details.


ad_page_contract {
	testing reports	
    @param start_year Year to start the report
    @param start_unit Month or week to start within the start_year
} {
    { start_date "" }
    { end_date "" }
    { level_of_detail 2 }
    project_id:integer,optional
    task_id:integer,optional
    company_id:integer,optional
    user_id:integer,optional
}

# ------------------------------------------------------------
# Security

# Label: Provides the security context for this report
# because it identifies unquely the report's Menu and
# its permissions.
set menu_label "reporting-timesheet-customer-project"

set current_user_id [ad_maybe_redirect_for_registration]

set read_p [db_string report_perms "
	select	im_object_permission_p(m.menu_id, :current_user_id, 'read')
	from	im_menus m
	where	m.label = :menu_label
" -default 'f']

if {![string equal "t" $read_p]} {
    ad_return_complaint 1 "
    [lang::message::lookup "" intranet-reporting.You_dont_have_permissions "You don't have the necessary permissions to view this page"]"
    return
}

# Check that Start & End-Date have correct format
if {"" != $start_date && ![regexp {[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]} $start_date]} {
    ad_return_complaint 1 "Start Date doesn't have the right format.<br>
    Current value: '$start_date'<br>
    Expected format: 'YYYY-MM-DD'"
}

if {"" != $end_date && ![regexp {[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9]} $end_date]} {
    ad_return_complaint 1 "End Date doesn't have the right format.<br>
    Current value: '$end_date'<br>
    Expected format: 'YYYY-MM-DD'"
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
if {$level_of_detail > 4} { set level_of_detail 4 }


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

set this_url [export_vars -base "/intranet-reporting/timesheet-customer-project" {start_date end_date} ]


# ------------------------------------------------------------
# Conditional SQL Where-Clause
#

set criteria [list]

if {[info exists company_id]} {
    lappend criteria "p.company_id = :company_id"
}

if {[info exists user_id]} {
    lappend criteria "h.user_id = :user_id"
}

if {[info exists task_id]} {
    lappend criteria "h.project_id = :task_id"
}

# Select project & subprojects
if {[info exists project_id]} {
    lappend criteria "p.project_id in (
	select
		p.project_id
	from
		im_projects p,
		im_projects parent_p
	where
		parent_p.project_id = :project_id
		and p.tree_sortkey between parent_p.tree_sortkey and tree_right(parent_p.tree_sortkey)
    )"
}

set where_clause [join $criteria " and\n            "]
if { ![empty_string_p $where_clause] } {
    set where_clause " and $where_clause"
}


# ------------------------------------------------------------
# Define the report - SQL, counters, headers and footers 
#

set inner_sql "
select
	h.day::date as date,
	h.note,
	to_char(h.day, 'J')::integer - to_char(to_date(:start_date, 'YYYY-MM-DD'), 'J')::integer as date_diff,
	h.user_id,
	p.project_id,
	p.company_id,
	h.hours,
	h.billing_rate
from
	im_hours h,
	im_projects p,
	cc_users u
where
	h.project_id = p.project_id
	and h.user_id = u.user_id
	and h.day >= to_date(:start_date, 'YYYY-MM-DD')
	and h.day < to_date(:end_date, 'YYYY-MM-DD')
	$where_clause
"

set sql "
select
	to_char(s.date, 'YYYY-MM-DD') as date,
	s.date_diff,
	s.note,
	u.user_id,
	u.first_names || ' ' || u.last_name as user_name,
	p.project_id,
	p.project_nr,
	p.project_name,
	c.company_id,
	c.company_path as company_nr,
	c.company_name,
	to_char(s.hours, '999,999.9') as hours,
	to_char(s.billing_rate, '999,999.9') as billing_rate
from
	($inner_sql) s,
	im_companies c,
	im_projects p,
	cc_users u
where
	s.user_id = u.user_id
	and s.company_id = c.company_id
	and s.project_id = p.project_id
order by
	s.company_id,
	p.project_id,
	u.user_id,
	s.date
"

set report_def [list \
    group_by company_nr \
    header {
	"\#colspan=99 <a href=$this_url&company_id=$company_id&level_of_detail=4 target=_blank><img src=/intranet/images/plus_9.gif border=0></a> 
	<b><a href=$company_url$company_id>$company_name</a></b>"
    } \
    content [list  \
	group_by project_nr \
	header {
	    $company_nr 
	    "\#colspan=99 <a href=$this_url&project_id=$project_id&level_of_detail=4 target=_blank><img src=/intranet/images/plus_9.gif border=0></a>
	    <b><a href=$project_url$project_id>$project_name</a></b>"
	} \
	content [list \
	    group_by user_id \
	    header {
		$company_nr 
		$project_nr 
		"\#colspan=99 <a href=$this_url&project_id=$project_id&user_id=$user_id&level_of_detail=4 target=_blank><img src=/intranet/images/plus_9.gif border=0></a>
		<b><a href=$user_url$user_id>$user_name</a></b>"
	    } \
	    content [list \
		    header {
			$company_nr
			$project_nr
			$user_name
			$date
			$hours
			$billing_rate
			$note
		    } \
		    content {} \
	    ] \
	    footer {
		$company_nr 
		$project_nr 
		$user_name
		""
		"<i>$hours_user_subtotal</i>"
		""
		""
	    } \
	] \
	footer {
    	    $company_nr 
	    $project_nr 
	    ""
	    ""
	    "<b>$hours_project_subtotal</b>"
	    ""
	    ""
	} \
    ] \
    footer {"" "" "" "" "" "" ""} \
]

# Global header/footer
set header0 {"Customer" "Project" "User" "Date" Hours Rate Note}
set footer0 {"" "" "" "" "" "" ""}

set hours_user_counter [list \
	pretty_name Hours \
	var hours_user_subtotal \
	reset \$user_id \
	expr \$hours
]

set hours_project_counter [list \
	pretty_name Hours \
	var hours_project_subtotal \
	reset \$project_id \
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
set levels {1 "Customer Only" 2 "Customer+Project" 3 "Customer+Project+User" 4 "All Details"} 

# ------------------------------------------------------------
# Start formatting the page
#

ad_return_top_of_page "
[im_header $page_title]
[im_navbar]
<form>
<table border=0 cellspacing=1 cellpadding=1>
<tr>
  <td class=form-label>Level of Details</td>
  <td class=form-widget>
    [im_select -translate_p 0 level_of_detail $levels $level_of_detail]
  </td>
</tr>
<tr>
  <td class=form-label>Start Date</td>
  <td class=form-widget>
    <input type=textfield name=start_date value=$start_date>
  </td>
</tr>
<tr>
  <td class=form-label>End Date</td>
  <td class=form-widget>
    <input type=textfield name=end_date value=$end_date>
  </td>
</tr>
<tr>
  <td></td>
  <td><input type=submit value=Submit></td>
</tr>
</table>
</form>

<table border=0 cellspacing=1 cellpadding=1>\n"

im_report_render_row \
    -row $header0 \
    -row_class "rowtitle" \
    -cell_class "rowtitle"


set footer_array_list [list]
set last_value_list [list]
set class "rowodd"
db_foreach sql $sql {

	set note [string_truncate -len 80 $note]

	im_report_display_footer \
	    -group_def $report_def \
	    -footer_array_list $footer_array_list \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class
	
	im_report_update_counters -counters $counters
	
	set last_value_list [im_report_render_header \
	    -group_def $report_def \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class
        ]

        set footer_array_list [im_report_render_footer \
	    -group_def $report_def \
	    -last_value_array_list $last_value_list \
	    -level_of_detail $level_of_detail \
	    -row_class $class \
	    -cell_class $class
        ]
}

im_report_display_footer \
    -group_def $report_def \
    -footer_array_list $footer_array_list \
    -last_value_array_list $last_value_list \
    -level_of_detail $level_of_detail \
    -display_all_footers_p 1 \
    -row_class $class \
    -cell_class $class

im_report_render_row \
    -row $footer0 \
    -row_class $class \
    -cell_class $class


ns_write "</table>\n[im_footer]\n"
