# /packages/intranet-timesheet2/www/hours_report_json.tcl
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
    { timescale "weekly" }
    { view_format "html" }
    { dimension "hours" }
    { extjs "store"}
}
set user_id 33049
ad_user_login $user_id
set json_lists [list]


# We need to set the overall hours per week an employee is working
# Make this a default for all for now.
set hours_per_week [expr 5 * [parameter::get -parameter TimesheetHoursPerDay -package_id [apm_package_id_from_key "intranet-timesheet2"]]] 

if {"" == $start_date} { 
    set start_date [db_string get_today "select to_char(sysdate,'YYYY-01-01') from dual"]   
}

if {"" == $end_date} { 
    # if no end_date is given, set it to six weeks in the future
    set end_date [db_string current_week "select to_char(sysdate + interval '6 weeks','YYYY-MM-DD') from dual"]
}

# Prepare the timescale headers
# Those can be week numbers or months

set current_date $start_date
set timescale_headers [list]
switch $timescale {
    weekly {
	while {$current_date<=$end_date} {
	    set current_week [db_string end_week "select extract(week from to_date(:current_date,'YYYY-MM-DD')) from dual"]   
	    lappend timescale_headers $current_week
	    set current_date [db_string current_week "select to_char(to_date(:current_date,'YYYY-MM-DD') + interval '1 week','YYYY-MM-DD') from dual"]
	}
	set timescale_sql "extract(week from day)"
    }
    default {
	while {$current_date<=$end_date} {
	    set current_month [db_string end_week "select extract(month from to_date(:current_date,'YYYY-MM-DD')) from dual"]   
	    lappend timescale_headers $current_month
	    set current_date [db_string current_month "select to_char(to_date(:current_date,'YYYY-MM-DD') + interval '1 month','YYYY-MM-DD') from dual"]
	}
	set timescale_sql "to_char(day,'YYMM')"
    }
}

if {$extjs == "model"} {
    set model_json_list "extend"
    lappend model_json_list "Ext.data.Model"

    set ts_list "user_project"
    lappend ts_list string
    lappend model_timescale_list [util::json::object::create $ts_list]

    foreach timescale_header $timescale_headers {
	set ts_list $timescale_header
	lappend ts_list string
	lappend model_timescale_list [util::json::object::create $ts_list]
    }
    lappend model_json_list "fields"
    lappend model_json_list [util::json::array::create $model_timescale_list]

    
    set json [util::json::gen [util::json::object::create $model_json_list]]
    ns_return 200 text/text $json
    ad_script_abort
}

if {$extjs == "column"} {
    set model_json_list "extend"
    lappend model_json_list "Ext.data.Model"
    
    # First column
    set ts_list "xtype"
    lappend ts_list "treecolumn"
    lappend ts_list "text"
    lappend ts_list "Nutzer/Projekt"
    lappend ts_list "flex"
    lappend ts_list "2"
    lappend ts_list "sortable"
    lappend ts_list "true"
    lappend ts_list "dataIndex"
    lappend ts_list "user_project"
    lappend model_timescale_list [util::json::object::create $ts_list]

    foreach timescale_header $timescale_headers {
	set ts_list [list text $timescale_header flex 1 dataIndex $timescale_header]
	lappend model_timescale_list [util::json::object::create $ts_list]
    }
    lappend model_json_list "fields"
    lappend model_json_list [util::json::array::create $model_timescale_list]

    
    set json [util::json::gen [util::json::object::create $model_json_list]]
    ns_return 200 text/text $json
    ad_script_abort
}

# ---------------------------------------------------------------
# Prepare the filters
# ---------------------------------------------------------------

set extra_wheres [list]
# Filter by owner_id
if {$owner_id != ""} {
    lappend extra_wheres "h.user_id = :owner_id"
}    

# Filter for projects
if {$project_id != ""} {
    # Get all hours for this project, including hours logged on
    # tasks (100) or tickets (101)
    lappend extra_wheres "(h.project_id in (	
              	   select p.project_id
		   from im_projects p, im_projects parent_p
                   where parent_p.project_id = :project_id
                   and p.tree_sortkey between parent_p.tree_sortkey and tree_right(parent_p.tree_sortkey)
                   and p.project_status_id not in (82)
		))"
}

# Filter for department_id
if { "" != $cost_center_id } {
        lappend extra_wheres "
        h.user_id in (select employee_id from im_employees where department_id in (select object_id from acs_object_context_index where ancestor_id = $cost_center_id) or h.user_id = :user_id)
"
}

if {$extra_wheres != ""} {
    set extra_where_sql "and [join $extra_wheres "\n and"]"
} else {
    set extra_where_sql ""
}

# Get the username / project combinations
# The projects are ordered by the sortkey and we store the indent
# level to later build the hierarchy
set user_list [list]
set sql "select username,
         project_name,
         p.project_id,
         employee_id,
         tree_sortkey,
         parent_id
    from im_projects p, im_employees e, users u, 
         (select distinct user_id,project_id from im_hours where day between :start_date and :end_date) h
    where u.user_id = h.user_id
      and p.project_id = h.project_id
      and e.employee_id = h.user_id
      and p.project_type_id not in (100,101)
          $extra_where_sql
    group by username,project_name,employee_id,p.project_id,p.tree_sortkey, parent_id
    order by username,tree_sortkey,project_name
"
db_foreach projects_info_query $sql {
    if {[lsearch $user_list $employee_id] < 0} {
	lappend user_list $employee_id
	set user_projects($employee_id) [list]
    }
    lappend user_projects($employee_id) $project_id
}

# Now go for the extra data

# If we want the percentages, we need to 
# Load the total hours a user has logged in case we are looking at the
# actuals or forecast

# Approved comes from the category type "Intranet Timesheet Conf Status"
if {$approved_only_p && [apm_package_installed_p "intranet-timesheet2-workflow"]} {
    set hours_sql "select sum(hours) as total, $timescale_sql as timescale_value, user_id
	from im_hours, im_timesheet_conf_objects tco
        where tco.conf_id = im_hours.conf_object_id and tco.conf_status_id = 17010
        and day between :start_date and :end_date
	group by user_id, timescale_value"
} else {
    set hours_sql "select sum(hours) as total, $timescale_sql as timescale_value, user_id
	from im_hours
        where day between :start_date and :end_date
	group by user_id, timescale_value"
}

# Get the total hours for the user for a certain timescale
db_foreach logged_hours $hours_sql {
    if {$user_id != "" && $timescale_value != ""} {
	set user_hours_${timescale_value}_${user_id} $total
    }
}

set json_list [list]
set counter 0

foreach user_id $user_list {
    # Initialize the JSON Object for the user
    set json_user_list [list]
    set user_json_projects [list]

    # Load the aggregated times for the user
    lappend json_user_list user_project
    lappend json_user_list [im_name_from_user_id $user_id]
    foreach timescale_header $timescale_headers {
	lappend json_user_list $timescale_header
	if {[info exists user_hours_${timescale_header}_$user_id]} {
	    lappend json_user_list [set user_hours_${timescale_header}_$user_id]
	} else {
	    lappend json_user_list ""
	}
    }
    
    # Make sure we not only have the leaf projects for the user but
    # also all parent_project_ids as well
    set user_project_list [im_parent_projects -project_ids $user_projects($user_id) -start_with_leaf]

    # Now loop through each project
    # The project list is already ordered from leaf to branch,
    # allowing us to append it to the parent_id
    set json_user_projects [list]
    set parent_project_ids [list]
    foreach project_id $user_project_list {
	db_1row project_info "select project_name, parent_id, (select 1 from im_projects where parent_id = :project_id limit 1) parent_p from im_projects where project_id = :project_id"

	# Get the timescale values for all projects, sorted by the
	# tree_sortkey, so we can change traverse the projects correctly.
	set timescale_value_sql "select sum(hours) as sum_hours,$timescale_sql as timescale_header
    		from im_hours
		where user_id = :user_id
                and project_id in (	
              	   select p.project_id
		   from im_projects p, im_projects parent_p
                   where parent_p.project_id = :project_id
                   and p.tree_sortkey between parent_p.tree_sortkey and tree_right(parent_p.tree_sortkey)
                   and p.project_status_id not in (82)
		)		   
		group by timescale_header
                order by timescale_header
         "

	# Store the value for the timescale for the project in an array
	# for later use.
	db_foreach timescale_info $timescale_value_sql {
	    if {"percentage" == $dimension} {
		if {[info exists user_hours_${dimension}_$employee_id]} {
		    set total [set user_hours_${dimension}_$employee_id]
		} else {
		    set total 0
		}
		if {0 < $total} {
		    set ${project_id}($timescale_header) "[expr round($sum_hours / $total *100)]"
		} 
	    } else {
		set ${project_id}($timescale_header) $sum_hours
	    }
	}


	# Now create the json for the project
	set json_project_list [list]
	lappend json_project_list user_project
	lappend json_project_list $project_name
	
	foreach timescale_header $timescale_headers {
	    lappend json_project_list $timescale_header
	    if {[info exists ${project_id}($timescale_header)]} {
		lappend json_project_list [set ${project_id}($timescale_header)]
	    } else {
		lappend json_project_list ""
	    }
	}

	# Find out if the project_id has subprojects. Then it is not a
	# leaf
	if {$parent_p != 1} {
	    lappend json_project_list leaf
	    lappend json_project_list true
	}
	lappend parent_project_ids $parent_id
	if {[lsearch $parent_project_ids $project_id]<0} {
	    # the project is not in the parent_project list, therefore
	    # no subproject has been called for it
	    lappend parent_project_ids $project_id
	} else {
	    lappend json_project_list "children"
	    lappend json_project_list [util::json::array::create $parent_json_list($project_id)]
	}


	# Make sure we have no " " " unescaped
	regsub -all {\"} $json_project_list {\\\"} json_list_project_list
	if {$parent_id == ""} {
	    ds_comment "$user_id $project_name"
	    lappend user_json_projects [util::json::object::create $json_project_list]
	} else {
	    lappend parent_json_list($parent_id) [util::json::object::create $json_project_list]
	}
    }

    # Wenn parent_id empty, dann hänge es an den user json
    # Wenn parent_id nicht empty, dann hänge es an den project json
    lappend json_user_list "children"
    lappend json_user_list [util::json::array::create $user_json_projects]

#    lappend json_user_list "children"
#    lappend json_user_list [util::json::gen [util::json::object::create [array get json_projects_array]]]
#    set json [util::json::gen [util::json::object::create $json_user_list]]
#    array unset json_projects_array
#    set json_user_array(children) [util::json::array::create $json_user_list]
#    set json [util::json::gen [util::json::object::create [array get json_user_array]]]

    lappend json_lists  [util::json::object::create $json_user_list]
    incr counter
    if {$counter >20} {
	break
    }
}
set json_array(children) [util::json::array::create $json_lists]
set json [util::json::gen [util::json::object::create [array get json_array]]]
ns_return 200 text/text $json
