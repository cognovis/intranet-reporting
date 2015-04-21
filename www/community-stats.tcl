# /packages/intranet-reporting/www/community-stats.tcl
#
# Copyright (c) 2003-2007 ]project-open[
#
# All rights reserved.
# Please see http://www.project-open.com/ for licensing.





set page_title [lang::message::lookup "" intranet-preporting.Community_stats "Community Statistics"]
set context_bar [im_context_bar $page_title]
set help "
	<b>Community Statistics</b>:<br>
	Shows statistics on the user in the system.
"

set bgcolor(0) " class=roweven "
set bgcolor(1) " class=rowodd "
set content ""
set cnt 0



# ------------------------------------------------------------
# Security

# Label: Provides the security context for this report
# because it identifies unquely the report's Menu and
# its permissions.
set menu_label "reporting-community-stats"
set current_user_id [ad_maybe_redirect_for_registration]

# Determine whether the current_user has read permissions. 
set read_p [im_menu_permission -menu_label $menu_label -user_id $current_user_id]

# Write out an error message if the current user doesn't have read permissions
if {!$read_p} {
    set message "You don't have the necessary permissions to view this page"
    ad_return_complaint 1 "<li>$message"
    ad_script_abort
}


# ------------------------------------------------------------
# User Statistics

set content "
	<table cellspacing=1 cellpadding=1>
	<tr class=rowtitle>
	  <td class=rowtitle colspan=2 align=center>[lang::message::lookup "" intranet-reporting.User_statistics "User Statistics"]</td>
	</tr>
"

set total_users [db_string total_users "
	select	count(*)
	from	persons
"]
append content "<tr><td $bgcolor([expr $cnt%2])>Total users in the system</td><td $bgcolor([expr $cnt%2])>$total_users</td></tr>\n"
incr cnt

append content "<tr><td class=rowplain colspan=2>&nbsp;</td></tr>\n"

# -----------------
# User Status

set users_status_sql "
	select	member_state,
		count(*) as users
	from	cc_users
	group by
		member_state
"
db_foreach users_status $users_status_sql {
    set status [lang::message::lookup "" intranet-reporting.User_status_$member_state $member_state]
    append content "<tr><td $bgcolor([expr $cnt%2])>Users with status $status</td><td $bgcolor([expr $cnt%2])>$users</td></tr>\n"
    incr cnt
}

# -----------------
# User Groups
db_1row user_groups_sql "
	select	sum(emp_p) as emps,
		sum(cust_p) as custs,
		sum(prov_p) as provs
	from (
		select	user_id,
			(select	count(*) from group_distinct_member_map m where m.group_id = 463 and m.member_id = u.user_id) as emp_p,
			(select	count(*) from group_distinct_member_map m where m.group_id = 461 and m.member_id = u.user_id) as cust_p,
			(select	count(*) from group_distinct_member_map m where m.group_id = 465 and m.member_id = u.user_id) as prov_p
		from	cc_users u
	) t
"

append content "<tr><td class=rowplain colspan=2>&nbsp;</td></tr>\n"
append content "<tr><td $bgcolor([expr $cnt%2])>Members of group 'Employees'</td><td $bgcolor([expr $cnt%2])>$emps</td></tr>\n"
incr cnt
append content "<tr><td $bgcolor([expr $cnt%2])>Members of group 'Customers'</td><td $bgcolor([expr $cnt%2])>$custs</td></tr>\n"
incr cnt
append content "<tr><td $bgcolor([expr $cnt%2])>Members of group 'Freelancers'</td><td $bgcolor([expr $cnt%2])>$provs</td></tr>\n"
incr cnt



append content "</table>\n<br>\n"




set monthly_regs_sql "
	select
		to_char(u.creation_date, 'YYYY-MM') as month,
		count(*) as cnt
	from	cc_users u
	group by to_char(u.creation_date, 'YYYY-MM')
	order by to_char(u.creation_date, 'YYYY-MM') DESC
	
"
append content [im_ad_hoc_query -format html -col_titles {"Month" "Registrations/Month"} $monthly_regs_sql]










