ad_page_contract {
	Shows a summary of the loged hours by all team members of a project(1 week).
	Only those users are shown that: -Have the permission to add hours or - Have the permission to add absences AND
	have atleast some absences logged

	@ param owner_id user concerned can be specified@ param project_id can be specified@ param workflow_key workflow_key to indicate
	if hours have been confirmed

	@ author Malte Sussdorff(malte.sussdorff@ cognovis.de)
} {
	{
		end_date ""
	} {
		start_date ""
	} {
		timescale "weekly"
	}
}

if {
	"" == $start_date
} {
	set start_date [db_string get_today "select to_char(sysdate,'YYYY-01-01') from dual"]
}

if {
	"" == $end_date
} {
	# if no end_date is given, set it to six weeks in the future
	set end_date [db_string current_week "select to_char(sysdate + interval '6 weeks','YYYY-MM-DD') from dual"]
}

set current_date $start_date
set timescale_headers [list]
switch $timescale {
	weekly {
		while {
			$current_date <= $end_date
		} {
			set current_week [db_string end_week "select extract(week from to_date(:current_date,'YYYY-MM-DD')) from dual"]
			lappend timescale_headers $current_week
			set current_date [db_string current_week "select to_char(to_date(:current_date,'YYYY-MM-DD') + interval '1 week','YYYY-MM-DD') from dual"]
		}
		set timescale_sql "extract(week from day)"
	}
	default {
		while {
			$current_date <= $end_date
		} {
			set current_month [db_string end_week "select extract(month from to_date(:current_date,'YYYY-MM-DD')) from dual"]
			lappend timescale_headers $current_month
			set current_date [db_string current_month "select to_char(to_date(:current_date,'YYYY-MM-DD') + interval '1 month','YYYY-MM-DD') from dual"]
		}
		set timescale_sql "to_char(day,'YYMM')"
	}
}

# First column
set ts_list [list "xtype" "treecolumn" "text" "Nutzer/Projekt" "flex" "2" "sortable" "true" "dataIndex" "user_project"]
lappend model_timescale_list [util::json::object::create $ts_list]

# Columns for the timescale
foreach timescale_header $timescale_headers {
	set ts_list [list text $timescale_header flex 1 dataIndex $timescale_header]
	lappend model_timescale_list [util::json::object::create $ts_list]
}
lappend model_json_list "columns"
lappend model_json_list [util::json::array::create $model_timescale_list]


set json [util::json::gen [util::json::object::create $model_json_list]]


ns_return 200 text/text "
Ext.define('PO.view.HoursReport', {
    extend: 'Ext.tree.Panel',

    height: 250,
    width: 400,
    title: 'Hours Report',
    store: 'HoursReport',
    rootVisible: false,
    useArrows: true,

    initComponent: function() {
        var me = this;

        Ext.applyIf(me, {
            viewConfig: {

            },
			[lindex $json 0]
        });

        me.callParent(arguments);
    }

});"

